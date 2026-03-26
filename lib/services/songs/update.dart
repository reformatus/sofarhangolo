import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'delete_for_song.dart';
import '../../data/log/logger.dart';
import 'package:queue/queue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/bank/bank.dart';
import '../../data/database.dart';
import '../../data/song/song.dart';
import '../bank/bank_api.dart';
import '../bank/bank_updated.dart';
import '../bank/update.dart';
import '../http/dio_provider.dart';

part 'update.g.dart';

bool isDone(
  ({int toUpdateCount, int updatedCount, int songsWithErrors})? record,
) {
  if (record == null) return false;
  return record.toUpdateCount == record.updatedCount + record.songsWithErrors;
}

double? getProgress(
  ({int toUpdateCount, int updatedCount, int songsWithErrors})? record,
) {
  if (record == null) return null;
  if (record.toUpdateCount == 0) return 1;
  return (record.updatedCount + record.songsWithErrors) / record.toUpdateCount;
}

/// Update all songs on all banks
@Riverpod(keepAlive: true)
Stream<Map<Bank, ({int toUpdateCount, int updatedCount, int songsWithErrors})?>>
updateAllBanksSongs(Ref ref) async* {
  final dio = ref.read(dioProvider);

  await updateBanks(dio);

  Map<Bank, ({int toUpdateCount, int updatedCount, int songsWithErrors})?>
  bankStates = Map.fromEntries(
    (await (db.banks.select()..where((b) => b.isEnabled)).get()).map(
      (e) => MapEntry(e, null),
    ),
  );

  // copy to new instance to avoid it getting changed during ui
  yield {...bankStates};

  for (var bankState in bankStates.entries) {
    try {
      await for (var newState in updateBankSongs(bankState.key, dio)) {
        bankStates[bankState.key] = newState;
        yield {...bankStates};
      }
    } catch (e, s) {
      log.severe('Hiba a ${bankState.key.name} frissítése közben:', e, s);
    }
  }
}

/// Update all songs in a bank
Stream<({int toUpdateCount, int updatedCount, int songsWithErrors})>
updateBankSongs(Bank bank, Dio dio) {
  final controller =
      StreamController<
        ({int toUpdateCount, int updatedCount, int songsWithErrors})
      >();

  unawaited(() async {
    try {
      final bankApi = BankApi(dio);
      // stay in indefinite loading state until we know protosong count
      // return protosong count for display
      List<ProtoSong> toUpdate;
      int? totalSongsInBank = bank.totalSongsInBank;
      if (bank.noCms) {
        // when the bank static without cms, update all songs if there have been changes.
        final remoteLastUpdated = await bankApi.getRemoteLastUpdated(bank);
        if (remoteLastUpdated != null &&
            bank.lastUpdated != null &&
            bank.lastUpdated!.isAfter(remoteLastUpdated)) {
          toUpdate = [];
        } else {
          toUpdate = await bankApi.getProtoSongs(bank);
          totalSongsInBank = toUpdate.length;
        }
      } else {
        toUpdate = await bankApi.getProtoSongs(bank, since: bank.lastUpdated);
        if (bank.lastUpdated == null) {
          totalSongsInBank = toUpdate.length;
        }
      }

      final persistedFailedSongs = bank.failedProtoSongs;
      if (persistedFailedSongs.isNotEmpty) {
        final Map<String, ProtoSong> mergedByUuid = {
          for (final protoSong in toUpdate) protoSong.uuid: protoSong,
        };
        for (final failedSong in persistedFailedSongs) {
          mergedByUuid.putIfAbsent(failedSong.uuid, () => failedSong);
        }
        toUpdate = mergedByUuid.values.toList(growable: false);
      }

      int updatedCount = 0;
      bool hadErrors = false;
      final Map<String, String> failedSongsByUuid = {};

      void emitProgress() {
        controller.add((
          toUpdateCount: toUpdate.length,
          updatedCount: updatedCount,
          songsWithErrors: failedSongsByUuid.length,
        ));
      }

      void markFailedProtoSong(ProtoSong protoSong) {
        hadErrors = true;
        failedSongsByUuid[protoSong.uuid] = protoSong.title;
        emitProgress();
      }

      Future<void> persistBankState() async {
        await (db.banks.update()..where((b) => b.id.equals(bank.id))).write(
          BanksCompanion(
            failedSongUuids: Value(
              Bank.encodeFailedProtoSongs(failedSongsByUuid),
            ),
            totalSongsInBank: Value.absentIfNull(totalSongsInBank),
          ),
        );
      }

      Future<void> upsertSong(Song song) async {
        try {
          await db
              .into(db.songs)
              .insert(
                song,
                mode: InsertMode.insertOrReplace,
              ); // TODO handle user modified data, etc

          deleteAssetsForSong(song);

          updatedCount++;
          emitProgress();
        } catch (f, t) {
          hadErrors = true;
          failedSongsByUuid[song.uuid] = song.title;
          emitProgress();
          log.severe(
            'Nem sikerült adatbázisba írni: "${song.title}"',
            f.toString(),
            t,
          );
        }
      }

      Future<void> processSingleSong(ProtoSong protoSong) async {
        try {
          final songs = await bankApi.getDetailsForSongs(bank, [
            protoSong.uuid,
          ]);
          final matchingSongs = songs.where(
            (song) => song.uuid == protoSong.uuid,
          );
          if (matchingSongs.isEmpty) {
            markFailedProtoSong(protoSong);
            log.severe(
              '"${protoSong.title}" lekérdezése sikeres volt, de a válaszban nem szerepelt a dal.',
              'UUID: ${protoSong.uuid}',
            );
            return;
          }

          for (final song in matchingSongs) {
            await upsertSong(song);
          }
        } catch (e, s) {
          markFailedProtoSong(protoSong);
          log.severe(
            'Nem sikerült lekérdezni: "${protoSong.title}"',
            e.toString(),
            s,
          );
        }
      }

      Future<void> processBatch(List<ProtoSong> protoSongs) async {
        if (protoSongs.isEmpty) return;

        if (protoSongs.length == 1) {
          await processSingleSong(protoSongs.single);
          return;
        }

        try {
          final songs = await bankApi.getDetailsForSongs(
            bank,
            protoSongs.map((e) => e.uuid).toList(),
          );

          final requestedUuids = protoSongs.map((e) => e.uuid).toSet();
          final returnedRequestedSongs = songs
              .where((song) => requestedUuids.contains(song.uuid))
              .toList();
          final returnedRequestedUuids = returnedRequestedSongs
              .map((song) => song.uuid)
              .toSet();

          for (final song in returnedRequestedSongs) {
            await upsertSong(song);
          }

          final missingProtoSongs = protoSongs
              .where(
                (protoSong) => !returnedRequestedUuids.contains(protoSong.uuid),
              )
              .toList();

          if (missingProtoSongs.isNotEmpty) {
            hadErrors = true;
            final missingTitles = missingProtoSongs
                .map((e) => e.title)
                .toList();
            final missingUuids = missingProtoSongs.map((e) => e.uuid).toList();
            log.info(
              '$missingTitles dalok hiányoznak a batch válaszból, egyenként újrapróbáljuk.',
              missingUuids.toString(),
            );
            for (final protoSong in missingProtoSongs) {
              await processSingleSong(protoSong);
            }
          }
        } catch (e, s) {
          hadErrors = true;
          final protoSongTitles = protoSongs.map((e) => e.title).toList();
          log.info(
            '$protoSongTitles dalok batch lekérdezése nem sikerült, egyedi lekérdezésekre váltunk.',
            'Hiba: $e',
            s,
          );
          for (final protoSong in protoSongs) {
            await processSingleSong(protoSong);
          }
        }
      }

      emitProgress();

      if (toUpdate.isNotEmpty) {
        final Queue queue = Queue(parallel: bank.parallelUpdateJobs);

        List<List<ProtoSong>> toUpdateBatches = [];
        for (
          var i = 0;
          i < toUpdate.length / bank.amountOfSongsInRequest;
          i++
        ) {
          int startIndex = i * bank.amountOfSongsInRequest;
          int endIndex = min(
            (i + 1) * bank.amountOfSongsInRequest,
            toUpdate.length,
          );
          toUpdateBatches.add(toUpdate.sublist(startIndex, endIndex));
        }

        for (List<ProtoSong> protoSongs in toUpdateBatches) {
          queue.add(() async {
            await processBatch(protoSongs);
          });
        }

        await for (int remaining in queue.remainingItems) {
          emitProgress();
          if (remaining == 0) break;
        }

        final songsWithErrors = failedSongsByUuid.length;
        if (songsWithErrors > 0) {
          log.warning(
            '${bank.name} tárból $songsWithErrors dal frissítése sikertelen volt!',
          );
        }

        await persistBankState();

        await setAsUpdatedNow(bank);
      }

      if (!hadErrors) {
        log.info('Minden dal frissítve: ${bank.name}');
      }

      return;
    } catch (e, s) {
      if (!controller.isClosed) {
        controller.addError(e, s);
      }
    } finally {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }());

  return controller.stream;
}
