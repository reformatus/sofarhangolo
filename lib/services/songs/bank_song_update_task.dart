import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:queue/queue.dart';

import '../../data/bank/bank.dart';
import '../../data/database.dart';
import '../../data/log/logger.dart';
import '../../data/song/song.dart';
import '../bank/bank_api.dart';
import '../bank/bank_updated.dart';
import '../task/background_task.dart';
import 'delete_for_song.dart';

class BankSongUpdateTask extends BackgroundTask {
  BankSongUpdateTask({required this.bank, required this.dio});

  final Bank bank;
  final Dio dio;

  int _toUpdateCount = 0;
  int _updatedCount = 0;
  int _songsWithErrors = 0;
  bool _hasResolvedWorkload = false;

  Uint8List? get logo => bank.logo;
  Uint8List? get tinyLogo => bank.tinyLogo;

  @override
  String get deduplicationKey => 'bank-song-update:${bank.uuid}';

  @override
  String get title => bank.name;

  @override
  String get subtitle {
    if (isPending) {
      return 'Várakozik a sorban';
    }

    if (!_hasResolvedWorkload) {
      return isFailed
          ? 'A frissítés megszakadt.'
          : 'Frissítendő dalok lekérdezése...';
    }

    if (_toUpdateCount == 0) {
      return isFailed ? 'A frissítés megszakadt.' : 'Minden friss.';
    }

    return '$_updatedCount ($_songsWithErrors hiba) / $_toUpdateCount frissítve';
  }

  @override
  double? get progress {
    if (!_hasResolvedWorkload) return null;
    if (_toUpdateCount == 0) return 1;

    return (_updatedCount + _songsWithErrors) / _toUpdateCount;
  }

  @override
  int get totalCount => _toUpdateCount;

  @override
  int get doneCount => _updatedCount;

  @override
  int get errorCount => _songsWithErrors;

  @override
  void resetProgress() {
    super.resetProgress();
    _toUpdateCount = 0;
    _updatedCount = 0;
    _songsWithErrors = 0;
    _hasResolvedWorkload = false;
  }

  @override
  Future<void> execute() async {
    try {
      final bankApi = BankApi(dio);

      List<ProtoSong> toUpdate;
      int? totalSongsInBank = bank.totalSongsInBank;

      if (bank.noCms) {
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
        final mergedByUuid = <String, ProtoSong>{
          for (final protoSong in toUpdate) protoSong.uuid: protoSong,
        };
        for (final failedSong in persistedFailedSongs) {
          mergedByUuid.putIfAbsent(failedSong.uuid, () => failedSong);
        }
        toUpdate = mergedByUuid.values.toList(growable: false);
      }

      _hasResolvedWorkload = true;
      _toUpdateCount = toUpdate.length;
      notifyListeners();

      bool hadErrors = false;
      final failedSongsByUuid = <String, String>{};

      void markFailedProtoSong(ProtoSong protoSong) {
        hadErrors = true;
        failedSongsByUuid[protoSong.uuid] = protoSong.title;
        _songsWithErrors = failedSongsByUuid.length;
        notifyListeners();
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
              .insert(song, mode: InsertMode.insertOrReplace);

          await deleteAssetsForSong(song);

          _updatedCount++;
          notifyListeners();
        } catch (error, stackTrace) {
          hadErrors = true;
          failedSongsByUuid[song.uuid] = song.title;
          _songsWithErrors = failedSongsByUuid.length;
          notifyListeners();

          log.severe(
            'Nem sikerült adatbázisba írni: "${song.title}"',
            error.toString(),
            stackTrace,
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
        } catch (error, stackTrace) {
          markFailedProtoSong(protoSong);
          log.severe(
            'Nem sikerült lekérdezni: "${protoSong.title}"',
            error.toString(),
            stackTrace,
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
            protoSongs.map((protoSong) => protoSong.uuid).toList(),
          );

          final requestedUuids = protoSongs
              .map((protoSong) => protoSong.uuid)
              .toSet();
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
                .map((protoSong) => protoSong.title)
                .toList();
            final missingUuids = missingProtoSongs
                .map((protoSong) => protoSong.uuid)
                .toList();
            log.info(
              '$missingTitles dalok hiányoznak a batch válaszból, egyenként újrapróbáljuk.',
              missingUuids.toString(),
            );

            for (final protoSong in missingProtoSongs) {
              await processSingleSong(protoSong);
            }
          }
        } catch (error, stackTrace) {
          hadErrors = true;
          final protoSongTitles = protoSongs
              .map((protoSong) => protoSong.title)
              .toList();
          log.info(
            '$protoSongTitles dalok batch lekérdezése nem sikerült, egyedi lekérdezésekre váltunk.',
            'Hiba: $error',
            stackTrace,
          );

          for (final protoSong in protoSongs) {
            await processSingleSong(protoSong);
          }
        }
      }

      if (toUpdate.isNotEmpty) {
        final queue = Queue(parallel: bank.parallelUpdateJobs);
        final toUpdateBatches = <List<ProtoSong>>[];

        for (
          var i = 0;
          i < toUpdate.length / bank.amountOfSongsInRequest;
          i++
        ) {
          final startIndex = i * bank.amountOfSongsInRequest;
          final endIndex = min(
            (i + 1) * bank.amountOfSongsInRequest,
            toUpdate.length,
          );
          toUpdateBatches.add(toUpdate.sublist(startIndex, endIndex));
        }

        for (final protoSongs in toUpdateBatches) {
          queue.add(() async {
            await processBatch(protoSongs);
          });
        }

        await for (final remaining in queue.remainingItems) {
          notifyListeners();
          if (remaining == 0) break;
        }

        if (_songsWithErrors > 0) {
          log.warning(
            '${bank.name} tárból $_songsWithErrors dal frissítése sikertelen volt!',
          );
        }

        await persistBankState();
        await setAsUpdatedNow(bank);
      }

      if (!hadErrors) {
        log.info('Minden dal frissítve: ${bank.name}');
      }
    } catch (error, stackTrace) {
      log.severe('Hiba a ${bank.name} frissítése közben:', error, stackTrace);
      rethrow;
    }
  }
}
