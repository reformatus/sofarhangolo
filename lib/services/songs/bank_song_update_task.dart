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
import 'variation_resolver.dart';

class BankSongUpdateTask extends BackgroundTask {
  BankSongUpdateTask({required this.bank, required this.dio});

  final Bank bank;
  final Dio dio;

  int _toUpdateCount = 0;
  int _updatedCount = 0;
  bool _hasResolvedWorkload = false;

  // Per-run state, re-initialized in [execute].
  bool _hadErrors = false;
  final Map<String, String> _failedSongsByUuid = {};
  final Set<String> _writtenUuids = {};
  final Set<String> _writtenVariationUuids = {};
  final Set<String> _listedUpdateUuids = {};
  bool _merging = false;

  int get _songsWithErrors => _failedSongsByUuid.length;

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

    return min(1.0, (_updatedCount + _songsWithErrors) / _toUpdateCount);
  }

  @override
  int get totalCount => _toUpdateCount;

  @override
  int get doneCount => _updatedCount;

  @override
  int get errorCount => _songsWithErrors;

  @override
  bool get logsFailures => true;

  @override
  void resetProgress() {
    super.resetProgress();
    _toUpdateCount = 0;
    _updatedCount = 0;
    _hasResolvedWorkload = false;
  }

  void _markFailed(String uuid, String title) {
    _hadErrors = true;
    _failedSongsByUuid[uuid] = title;
    notifyListeners();
  }

  Future<void> _persistBankState(int? totalSongsInBank) async {
    await (db.banks.update()..where((b) => b.id.equals(bank.id))).write(
      BanksCompanion(
        failedSongUuids: Value(Bank.encodeFailedProtoSongs(_failedSongsByUuid)),
        totalSongsInBank: Value.absentIfNull(totalSongsInBank),
      ),
    );
  }

  Future<void> _upsertSong(Song song) async {
    try {
      await db.into(db.songs).insert(song, mode: InsertMode.insertOrReplace);

      await deleteAssetsForSong(song);

      if (_merging) {
        _updatedCount++;
        // Songs the bank did not list grow the workload here; listed ones
        // were already counted when the workload was resolved.
        if (_listedUpdateUuids.add(song.uuid)) _toUpdateCount++;
      } else if (song.variationOf == null) {
        // Variation rows are stored raw here and settled by the merge phase,
        // so they are counted there instead.
        _updatedCount++;
      }
      _writtenUuids.add(song.uuid);
      if (song.variationOf != null) _writtenVariationUuids.add(song.uuid);
      notifyListeners();
    } catch (error, stackTrace) {
      _markFailed(song.uuid, song.title);
      log.severe(
        'Nem sikerült adatbázisba írni: "${song.title}"',
        error.toString(),
        stackTrace,
      );
    }
  }

  /// Resolves which songs need updating and the bank's total song count.
  Future<(List<ProtoSong>, int?)> _resolveWorkload(BankApi bankApi) async {
    var totalSongsInBank = bank.totalSongsInBank;

    // Fetch songs that were updated in the bank
    final List<ProtoSong> toUpdate;
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

    // Add previously failed song to the update list
    final persistedFailedSongs = bank.failedProtoSongs;
    if (persistedFailedSongs.isNotEmpty) {
      final mergedByUuid = <String, ProtoSong>{
        for (final protoSong in toUpdate) protoSong.uuid: protoSong,
      };
      for (final failedSong in persistedFailedSongs) {
        mergedByUuid.putIfAbsent(failedSong.uuid, () => failedSong);
      }
      return (mergedByUuid.values.toList(growable: false), totalSongsInBank);
    }

    return (toUpdate, totalSongsInBank);
  }

  /// Re-merges the variation chains affected by this run's writes and writes
  /// back the songs whose merged content changed. Never accesses the API.
  Future<void> _mergeVariations() async {
    if (_writtenUuids.isEmpty) return;
    _merging = true;

    // Every variation below a written song may inherit its values, so
    // collect the affected chains level by level in the database.
    var frontier = _writtenUuids.toSet();
    final affected = <String>{};
    while (frontier.isNotEmpty) {
      final children =
          await (db.songs.select()
                ..where((song) => song.variationOf.isIn(frontier)))
              .get();
      frontier = {
        for (final child in children)
          if (affected.add(child.uuid)) child.uuid,
      };
    }

    // Written variations were stored raw this run and need re-merging too.
    final workset = affected..addAll(_writtenVariationUuids);
    final reportedFailures = <String>{};

    for (final uuid in workset.toList()..sort()) {
      final stored = await _loadSong(uuid);
      // Rows without ownership metadata are frozen and never re-merged.
      if (stored == null || stored.ownership == null) continue;

      final (resolved, error) = await resolveVariationChain(stored, _loadSong);
      if (error != null) {
        if (reportedFailures.add(resolved.uuid)) {
          _markFailed(resolved.uuid, resolved.title);
          switch (error.kind) {
            case VariationMergeErrorKind.cyclicChain:
              log.warning(
                'Cirkuláris variációlánc, a dal helyben nem egyesíthető:',
                '"${resolved.title}" (UUID: ${resolved.uuid})',
              );
            case VariationMergeErrorKind.tooDeep:
              log.warning(
                'Túl mély variációlánc, a dal helyben nem egyesíthető:',
                '"${resolved.title}" (UUID: ${resolved.uuid})',
              );
          }
        }
        continue;
      }
      if (!resolved.sameMergeableContentAs(stored)) {
        await _upsertSong(resolved);
      }
    }
    _merging = false;
  }

  Future<Song?> _loadSong(String uuid) {
    return (db.songs.select()..where((song) => song.uuid.equals(uuid)))
        .getSingleOrNull();
  }

  @override
  Future<void> execute() async {
    try {
      _hadErrors = false;
      _failedSongsByUuid.clear();
      _writtenUuids.clear();
      _writtenVariationUuids.clear();
      _listedUpdateUuids.clear();
      _merging = false;

      final bankApi = BankApi(dio);

      final (toUpdate, totalSongsInBank) = await _resolveWorkload(bankApi);

      _hasResolvedWorkload = true;
      _toUpdateCount = toUpdate.length;
      _listedUpdateUuids.addAll(toUpdate.map((protoSong) => protoSong.uuid));
      notifyListeners();

      Future<void> processSingleSong(ProtoSong protoSong) async {
        try {
          final songs = await bankApi.getDetailsForSongs(bank, [
            protoSong.uuid,
          ]);
          final matchingSongs = songs.where(
            (song) => song.uuid == protoSong.uuid,
          );

          if (matchingSongs.isEmpty) {
            _markFailed(protoSong.uuid, protoSong.title);
            log.severe(
              '"${protoSong.title}" lekérdezése sikeres volt, de a válaszban nem szerepelt a dal.',
              'UUID: ${protoSong.uuid}',
            );
            return;
          }

          for (final song in matchingSongs) {
            await _upsertSong(song);
          }
        } catch (error, stackTrace) {
          _markFailed(protoSong.uuid, protoSong.title);
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
            await _upsertSong(song);
          }

          final missingProtoSongs = protoSongs
              .where(
                (protoSong) => !returnedRequestedUuids.contains(protoSong.uuid),
              )
              .toList();

          if (missingProtoSongs.isNotEmpty) {
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
      }

      await _mergeVariations();

      // Persisted unconditionally so variation-merge failures and old
      // last-updated state survive as well, not only download failures.
      await _persistBankState(totalSongsInBank);

      await setAsUpdatedNow(bank);

      if (!_hadErrors) {
        log.info('Minden dal frissítve: ${bank.name}');
      }
    } catch (error, stackTrace) {
      log.severe('Hiba a ${bank.name} frissítése közben:', error, stackTrace);
      rethrow;
    }
  }
}
