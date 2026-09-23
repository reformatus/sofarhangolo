import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/bank_song_update_task.dart';

import '../harness/test_harness.dart';

void main() {
  group('updateBankSongs asset invalidation', () {
    late LyricDatabase testDb;
    late Dio dio;

    setUp(() async {
      testDb = createTestDatabase();
      db = testDb;
      await db.customStatement('PRAGMA foreign_keys = OFF');
      dio = createMockDio();
    });

    tearDown(() async {
      await testDb.close();
    });

    Future<Bank> insertBank() async {
      await db
          .into(db.banks)
          .insert(
            BanksCompanion.insert(
              uuid: 'bank-1',
              name: 'Test Bank',
              baseUrl: Uri.parse('https://example.com/api'),
              parallelUpdateJobs: 1,
              amountOfSongsInRequest: 1,
              noCms: false,
              songFields: {},
              isEnabled: true,
              isOfflineMode: false,
            ),
          );

      return db.select(db.banks).getSingle();
    }

    test('deletes assets when song content changes', () async {
      final bank = await insertBank();
      final oldSong = Song.fromBankApiJson({
        'uuid': 'song-1',
        'title': 'Song 1',
        'lyrics': 'Amazing grace',
        'lyricsFormat': 'opensong',
        'pdf': '/old.pdf',
      }, sourceBank: bank);

      await db.into(db.songs).insert(oldSong, mode: InsertMode.insertOrReplace);
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              songUuid: 'song-1',
              sourceUrl: 'https://example.com/api/old.pdf',
              fieldName: 'pdf',
              content: Uint8List.fromList([1, 2, 3]),
            ),
          );

      dio.httpClientAdapter = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Song 1"}]',
              200,
            );
          }

          if (options.path.contains('/song/song-1')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Song 1","lyrics":"Amazing grace","lyricsFormat":"opensong","pdf":"/new.pdf"}]',
              200,
            );
          }

          return ResponseBody.fromString('[]', 200);
        },
      );

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      final assets = await db.select(db.assets).get();
      expect(assets, isEmpty);

      final updatedSong =
          await (db.songs.select()..where((s) => s.uuid.equals('song-1')))
              .getSingle();
      expect(updatedSong.contentMap['pdf'], equals('/new.pdf'));
    });

    test(
      'stores decoded lyrics and metadata from escaped API payloads',
      () async {
        final bank = await insertBank();

        dio.httpClientAdapter = RecordingHttpAdapter(
          responseBuilder: (options) {
            if (options.path.contains('/songs')) {
              return ResponseBody.fromString(
                '[{"uuid":"song-1","title":"Tom &amp; Jerry"}]',
                200,
              );
            }

            if (options.path.contains('/song/song-1')) {
              return ResponseBody.fromString(
                '[{"uuid":"song-1","title":"Tom &amp; Jerry","lyrics":"[V1]\\n A &amp; B","lyrics_format":"opensong","composer":"John &amp; Jane"}]',
                200,
              );
            }

            return ResponseBody.fromString('[]', 200);
          },
        );

        final task = BankSongUpdateTask(bank: bank, dio: dio);
        await task.run();

        final updatedSong =
            await (db.songs.select()..where((s) => s.uuid.equals('song-1')))
                .getSingle();
        expect(updatedSong.title, equals('Tom & Jerry'));
        expect(updatedSong.lyrics, equals('[V1]\n A & B'));
        expect(updatedSong.contentMap['composer'], equals('John & Jane'));
      },
    );

    test('keeps assets for unrelated songs', () async {
      final bank = await insertBank();
      final existingSong = Song.fromBankApiJson({
        'uuid': 'song-1',
        'title': 'Song 1',
        'lyrics': 'Amazing grace',
        'lyricsFormat': 'opensong',
        'pdf': '/same.pdf',
      }, sourceBank: bank);

      await db
          .into(db.songs)
          .insert(existingSong, mode: InsertMode.insertOrReplace);
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              songUuid: 'song-1',
              sourceUrl: 'https://example.com/api/same.pdf',
              fieldName: 'pdf',
              content: Uint8List.fromList([9, 9, 9]),
            ),
          );

      final unrelatedSong = Song.fromBankApiJson({
        'uuid': 'song-2',
        'title': 'Song 2',
        'lyrics': 'Second song',
        'lyricsFormat': 'opensong',
        'pdf': '/other.pdf',
      }, sourceBank: bank);

      await db
          .into(db.songs)
          .insert(unrelatedSong, mode: InsertMode.insertOrReplace);
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              songUuid: 'song-2',
              sourceUrl: 'https://example.com/api/other.pdf',
              fieldName: 'pdf',
              content: Uint8List.fromList([7, 7, 7]),
            ),
          );

      dio.httpClientAdapter = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Song 1"}]',
              200,
            );
          }

          if (options.path.contains('/song/song-1')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Song 1","lyrics":"Amazing grace","lyricsFormat":"opensong","pdf":"/same.pdf"}]',
              200,
            );
          }

          return ResponseBody.fromString('[]', 200);
        },
      );

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      final assets = await db.select(db.assets).get();
      expect(assets, hasLength(1));
      expect(assets.first.songUuid, equals('song-2'));
      expect(
        assets.first.sourceUrl,
        equals('https://example.com/api/other.pdf'),
      );
    });

    test(
      'deletes assets even when updated song payload is unchanged',
      () async {
        final bank = await insertBank();
        final existingSong = Song.fromBankApiJson({
          'uuid': 'song-1',
          'title': 'Song 1',
          'lyrics': 'Amazing grace',
          'lyricsFormat': 'opensong',
          'pdf': '/same.pdf',
        }, sourceBank: bank);

        await db
            .into(db.songs)
            .insert(existingSong, mode: InsertMode.insertOrReplace);
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                songUuid: 'song-1',
                sourceUrl: 'https://example.com/api/same.pdf',
                fieldName: 'pdf',
                content: Uint8List.fromList([4, 5, 6]),
              ),
            );

        dio.httpClientAdapter = RecordingHttpAdapter(
          responseBuilder: (options) {
            if (options.path.contains('/songs')) {
              return ResponseBody.fromString(
                '[{"uuid":"song-1","title":"Song 1"}]',
                200,
              );
            }

            if (options.path.contains('/song/song-1')) {
              return ResponseBody.fromString(
                '[{"uuid":"song-1","title":"Song 1","lyrics":"Amazing grace","lyricsFormat":"opensong","pdf":"/same.pdf"}]',
                200,
              );
            }

            return ResponseBody.fromString('[]', 200);
          },
        );

        final task = BankSongUpdateTask(bank: bank, dio: dio);
        await task.run();

        final assets = await db.select(db.assets).get();
        expect(assets, isEmpty);
      },
    );

    test('persists failed songs and retries them on next run', () async {
      final bank = await insertBank();

      dio.httpClientAdapter = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Song &amp; 1"}]',
              200,
            );
          }

          if (options.path.contains('/song/song-1')) {
            return ResponseBody.fromString('server error', 500);
          }

          return ResponseBody.fromString('[]', 200);
        },
      );

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      final bankAfterFirstRun =
          await (db.banks.select()..where((b) => b.uuid.equals(bank.uuid)))
              .getSingle();
      expect(bankAfterFirstRun.failedProtoSongs.map((e) => e.uuid), ['song-1']);
      expect(bankAfterFirstRun.failedProtoSongs.map((e) => e.title), [
        'Song & 1',
      ]);

      final adapter = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString('[]', 200);
          }

          if (options.path.contains('/song/song-1')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Song 1","lyrics":"Line","lyricsFormat":"opensong"}]',
              200,
            );
          }

          return ResponseBody.fromString('[]', 200);
        },
      );
      dio.httpClientAdapter = adapter;

      final retryTask = BankSongUpdateTask(bank: bankAfterFirstRun, dio: dio);
      await retryTask.run();

      expect(
        adapter.requests.any((r) => r.path.contains('/song/song-1')),
        isTrue,
      );

      final bankAfterSecondRun =
          await (db.banks.select()..where((b) => b.uuid.equals(bank.uuid)))
              .getSingle();
      expect(bankAfterSecondRun.failedProtoSongs, isEmpty);
    });

    test('sets totalSongsInBank on first full sync', () async {
      final bank = await insertBank();

      dio.httpClientAdapter = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Song 1"},{"uuid":"song-2","title":"Song 2"}]',
              200,
            );
          }

          if (options.path.contains('/song/song-1')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Song 1","lyrics":"Line","lyricsFormat":"opensong"}]',
              200,
            );
          }

          if (options.path.contains('/song/song-2')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-2","title":"Song 2","lyrics":"Line","lyricsFormat":"opensong"}]',
              200,
            );
          }

          return ResponseBody.fromString('[]', 200);
        },
      );

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      final updatedBank =
          await (db.banks.select()..where((b) => b.uuid.equals(bank.uuid)))
              .getSingle();
      expect(updatedBank.totalSongsInBank, 2);
    });

    test('tracks progress and errors through task fields', () async {
      final bank = await insertBank();

      dio.httpClientAdapter = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Song 1"},{"uuid":"song-2","title":"Song 2"}]',
              200,
            );
          }

          if (options.path.contains('/song/song-1')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Song 1","lyrics":"Line","lyricsFormat":"opensong"}]',
              200,
            );
          }

          if (options.path.contains('/song/song-2')) {
            return ResponseBody.fromString('server error', 500);
          }

          return ResponseBody.fromString('[]', 200);
        },
      );

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      expect(task.totalCount, 2);
      expect(task.doneCount, 1);
      expect(task.errorCount, 1);
      expect(task.progress, 1);
      expect(task.isCompleted, isTrue);
    });
  });

  group('variation resolution through the update task', () {
    late LyricDatabase testDb;
    late Dio dio;

    setUp(() async {
      testDb = createTestDatabase();
      db = testDb;
      await db.customStatement('PRAGMA foreign_keys = OFF');
      dio = createMockDio();
    });

    tearDown(() async {
      await testDb.close();
    });

    Future<Bank> insertBank() async {
      await db
          .into(db.banks)
          .insert(
            BanksCompanion.insert(
              uuid: 'bank-1',
              name: 'Test Bank',
              baseUrl: Uri.parse('https://example.com/api'),
              parallelUpdateJobs: 1,
              amountOfSongsInRequest: 1,
              noCms: false,
              songFields: {},
              isEnabled: true,
              isOfflineMode: false,
            ),
          );

      return db.select(db.banks).getSingle();
    }

    Future<Song> songByUuid(String uuid) =>
        (db.songs.select()..where((s) => s.uuid.equals(uuid))).getSingle();

    test(
      'a root song becoming a variation keeps owned and inherits unowned',
      () async {
        final bank = await insertBank();
        await db
            .into(db.songs)
            .insert(
              Song.fromBankApiJson({
                'uuid': 'song-t',
                'title': 'Song T',
                'lyrics': 'T lyrics',
                'lyricsFormat': 'opensong',
                'composer': 'Composer T',
                'arranger': 'Arranger T',
              }, sourceBank: bank),
              mode: InsertMode.insertOrReplace,
            );

        dio.httpClientAdapter = RecordingHttpAdapter(
          responseBuilder: (options) {
            if (options.path.contains('/songs')) {
              return ResponseBody.fromString(
                '[{"uuid":"song-s","title":"Song S"}]',
                200,
              );
            }

            if (options.path.contains('/song/song-s')) {
              return ResponseBody.fromString(
                '[{"uuid":"song-s","title":"Song S","lyrics":"S lyrics","lyrics_format":"opensong","composer":"Composer S","variation_of":"song-t"}]',
                200,
              );
            }

            return ResponseBody.fromString('[]', 200);
          },
        );

        final task = BankSongUpdateTask(bank: bank, dio: dio);
        await task.run();

        final s = await songByUuid('song-s');
        expect(s.variationOf, equals('song-t'));
        expect(
          s.contentMap,
          equals({'composer': 'Composer S', 'arranger': 'Arranger T'}),
        );
        // Arranger was inherited, not owned by S itself.
        expect(s.ownership!.contentKeys, equals({'composer'}));

        final t = await songByUuid('song-t');
        expect(t.variationOf, isNull);
        expect(
          t.contentMap,
          equals({'composer': 'Composer T', 'arranger': 'Arranger T'}),
        );
      },
    );

    test('a changed parent ripples into an unlisted variation child', () async {
      final bank = await insertBank();
      await db
          .into(db.songs)
          .insert(
            Song.fromBankApiJson({
              'uuid': 'song-t',
              'title': 'Song T',
              'lyrics': 'T lyrics',
              'lyricsFormat': 'opensong',
              'composer': 'Composer T',
              'arranger': 'Arranger T',
            }, sourceBank: bank),
            mode: InsertMode.insertOrReplace,
          );
      await db
          .into(db.songs)
          .insert(
            Song.fromBankApiJson({
              'uuid': 'song-s',
              'title': 'Song S',
              'lyrics': 'S lyrics',
              'lyricsFormat': 'opensong',
              'composer': 'Composer S',
              'variation_of': 'song-t',
            }, sourceBank: bank),
            mode: InsertMode.insertOrReplace,
          );

      dio.httpClientAdapter = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-t","title":"Song T"}]',
              200,
            );
          }

          if (options.path.contains('/song/song-t')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-t","title":"Song T","lyrics":"T lyrics","lyrics_format":"opensong","composer":"Composer T","arranger":"Arranger T2"}]',
              200,
            );
          }

          return ResponseBody.fromString('[]', 200);
        },
      );

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      final t = await songByUuid('song-t');
      expect(t.contentMap['arranger'], equals('Arranger T2'));

      final s = await songByUuid('song-s');
      expect(s.variationOf, equals('song-t'));
      expect(
        s.contentMap,
        equals({'composer': 'Composer S', 'arranger': 'Arranger T2'}),
      );
      expect(s.ownership!.contentKeys, equals({'composer'}));
    });

    test(
      'a frozen parent still provides inherited values through the task',
      () async {
        final bank = await insertBank();
        await db
            .into(db.songs)
            .insert(
              // Legacy row without ownership metadata: frozen, but readable.
              Song(
                uuid: 'song-t',
                title: 'Song T',
                lyrics: 'T lyrics',
                keyField: const [],
                contentMap: const {'composer': 'Composer T'},
                sourceBank: 'bank-1',
              ),
              mode: InsertMode.insertOrReplace,
            );

        dio.httpClientAdapter = RecordingHttpAdapter(
          responseBuilder: (options) {
            if (options.path.contains('/songs')) {
              return ResponseBody.fromString(
                '[{"uuid":"song-s","title":"Song S"}]',
                200,
              );
            }

            if (options.path.contains('/song/song-s')) {
              return ResponseBody.fromString(
                '[{"uuid":"song-s","title":"Song S","lyrics":"S lyrics","lyrics_format":"opensong","variation_of":"song-t"}]',
                200,
              );
            }

            return ResponseBody.fromString('[]', 200);
          },
        );

        final task = BankSongUpdateTask(bank: bank, dio: dio);
        await task.run();

        final s = await songByUuid('song-s');
        expect(s.variationOf, equals('song-t'));
        expect(s.contentMap, equals({'composer': 'Composer T'}));
        expect(s.ownership, isNotNull);
        expect(s.ownership!.contentKeys, isEmpty);

        final t = await songByUuid('song-t');
        expect(t.ownership, isNull);
        expect(t.contentMap, equals({'composer': 'Composer T'}));
      },
    );

    test(
      'a frozen variation child is left untouched when its root changes',
      () async {
        final bank = await insertBank();
        await db
            .into(db.songs)
            .insert(
              Song.fromBankApiJson({
                'uuid': 'song-r',
                'title': 'Song R',
                'lyrics': 'R lyrics',
                'lyricsFormat': 'opensong',
                'composer': 'Old Composer',
              }, sourceBank: bank),
              mode: InsertMode.insertOrReplace,
            );
        await db
            .into(db.songs)
            .insert(
              Song(
                uuid: 'song-t',
                title: 'Song T',
                lyrics: 'T lyrics',
                variationOf: 'song-r',
                keyField: const [],
                contentMap: const {
                  'composer': 'Composer T',
                  'arranger': 'Arranger T',
                },
                sourceBank: 'bank-1',
              ),
              mode: InsertMode.insertOrReplace,
            );

        dio.httpClientAdapter = RecordingHttpAdapter(
          responseBuilder: (options) {
            if (options.path.contains('/songs')) {
              return ResponseBody.fromString(
                '[{"uuid":"song-r","title":"Song R"}]',
                200,
              );
            }

            if (options.path.contains('/song/song-r')) {
              return ResponseBody.fromString(
                '[{"uuid":"song-r","title":"Song R","lyrics":"R lyrics","lyrics_format":"opensong","composer":"New Composer"}]',
                200,
              );
            }

            return ResponseBody.fromString('[]', 200);
          },
        );

        final task = BankSongUpdateTask(bank: bank, dio: dio);
        await task.run();

        final r = await songByUuid('song-r');
        expect(r.contentMap['composer'], equals('New Composer'));

        final t = await songByUuid('song-t');
        expect(t.ownership, isNull);
        expect(t.variationOf, equals('song-r'));
        expect(
          t.contentMap,
          equals({'composer': 'Composer T', 'arranger': 'Arranger T'}),
        );
      },
    );
  });

  group('counters and error containment through the update task', () {
    late LyricDatabase testDb;
    late Dio dio;

    setUp(() async {
      testDb = createTestDatabase();
      db = testDb;
      await db.customStatement('PRAGMA foreign_keys = OFF');
      dio = createMockDio();
    });

    tearDown(() async {
      await testDb.close();
    });

    Future<Bank> insertBank() async {
      await db
          .into(db.banks)
          .insert(
            BanksCompanion.insert(
              uuid: 'bank-1',
              name: 'Test Bank',
              baseUrl: Uri.parse('https://example.com/api'),
              parallelUpdateJobs: 1,
              amountOfSongsInRequest: 1,
              noCms: false,
              songFields: {},
              isEnabled: true,
              isOfflineMode: false,
            ),
          );

      return db.select(db.banks).getSingle();
    }

    Future<Song> songByUuid(String uuid) =>
        (db.songs.select()..where((s) => s.uuid.equals(uuid))).getSingle();

    Future<Bank> bankByUuid(String uuid) =>
        (db.banks.select()..where((b) => b.uuid.equals(uuid))).getSingle();

    void mockSync({required String listedJson, required String detailJson}) {
      dio.httpClientAdapter = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString(listedJson, 200);
          }

          if (options.path.contains('/song/')) {
            return ResponseBody.fromString(detailJson, 200);
          }

          return ResponseBody.fromString('[]', 200);
        },
      );
    }

    test('merge rewrite of a listed variation is not counted twice', () async {
      final bank = await insertBank();
      await db
          .into(db.songs)
          .insert(
            Song.fromBankApiJson({
              'uuid': 'song-t',
              'title': 'Song T',
              'lyrics': 'T lyrics',
              'lyricsFormat': 'opensong',
              'composer': 'Composer T',
              'arranger': 'Arranger T',
            }, sourceBank: bank),
            mode: InsertMode.insertOrReplace,
          );

      mockSync(
        listedJson: '[{"uuid":"song-s","title":"Song S"}]',
        detailJson:
            '[{"uuid":"song-s","title":"Song S","lyrics":"S lyrics",'
            '"lyrics_format":"opensong","variation_of":"song-t"}]',
      );

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      expect(task.totalCount, 1);
      expect(task.doneCount, 1);
      expect(task.errorCount, 0);
      expect(task.doneCount + task.errorCount, task.totalCount);

      final s = await songByUuid('song-s');
      expect(
        s.contentMap,
        equals({'composer': 'Composer T', 'arranger': 'Arranger T'}),
      );
      expect(s.ownership!.contentKeys, isEmpty);
    });

    test('too-deep chains count once and fail once at the cap', () async {
      final bank = await insertBank();

      mockSync(
        listedJson: '[{"uuid":"song-t","title":"Song T"}]',
        detailJson:
            '[{"uuid":"song-t","title":"Song T","lyrics":"T lyrics",'
            '"lyrics_format":"opensong","composer":"New Composer",'
            '"arranger":"Arranger T2"}]',
      );

      for (var i = 1; i <= 6; i++) {
        await db
            .into(db.songs)
            .insert(
              Song.fromBankApiJson({
                'uuid': 'song-s$i',
                'title': 'Song S$i',
                'lyrics': 'S$i lyrics',
                'lyricsFormat': 'opensong',
                'variation_of': i == 1 ? 'song-t' : 'song-s${i - 1}',
              }, sourceBank: bank),
              mode: InsertMode.insertOrReplace,
            );
      }

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      expect(task.totalCount, 7);
      expect(task.doneCount, 6);
      expect(task.errorCount, 1);
      expect(task.doneCount + task.errorCount, task.totalCount);

      final s1 = await songByUuid('song-s1');
      expect(s1.contentMap['composer'], equals('New Composer'));
      final s5 = await songByUuid('song-s5');
      expect(s5.contentMap['composer'], equals('New Composer'));
      final s6 = await songByUuid('song-s6');
      expect(s6.contentMap, isEmpty);
    });

    test('a second sync rewrites nothing when content already merged', () async {
      final bank = await insertBank();
      await db
          .into(db.songs)
          .insert(
            Song.fromBankApiJson({
              'uuid': 'song-t',
              'title': 'Song T',
              'lyrics': 'T lyrics',
              'lyricsFormat': 'opensong',
              'composer': 'Old Composer',
            }, sourceBank: bank),
            mode: InsertMode.insertOrReplace,
          );
      await db
          .into(db.songs)
          .insert(
            Song.fromBankApiJson({
              'uuid': 'song-s',
              'title': 'Song S',
              'lyrics': 'S lyrics',
              'lyricsFormat': 'opensong',
              'variation_of': 'song-t',
            }, sourceBank: bank),
            mode: InsertMode.insertOrReplace,
          );

      mockSync(
        listedJson: '[{"uuid":"song-t","title":"Song T"}]',
        detailJson:
            '[{"uuid":"song-t","title":"Song T","lyrics":"T lyrics",'
            '"lyrics_format":"opensong","composer":"New Composer"}]',
      );

      final firstTask = BankSongUpdateTask(bank: bank, dio: dio);
      await firstTask.run();

      final sAfterFirstRun = await songByUuid('song-s');
      expect(sAfterFirstRun.contentMap['composer'], equals('New Composer'));

      final secondTask = BankSongUpdateTask(
        bank: await bankByUuid(bank.uuid),
        dio: dio,
      );
      await secondTask.run();

      expect(secondTask.totalCount, 1);
      expect(secondTask.doneCount, 1);
      expect(secondTask.errorCount, 0);

      final t = await songByUuid('song-t');
      final s = await songByUuid('song-s');
      expect(t.contentMap['composer'], equals('New Composer'));
      expect(s.contentMap, equals(sAfterFirstRun.contentMap));
      expect(s.ownership!.contentKeys, isEmpty);
    });

    test('merge failures are persisted and bank state survives', () async {
      final bank = await insertBank();

      mockSync(
        listedJson: '[{"uuid":"song-t","title":"Song T"}]',
        detailJson:
            '[{"uuid":"song-t","title":"Song T","lyrics":"T lyrics",'
            '"lyrics_format":"opensong","composer":"New Composer"}]',
      );

      for (var i = 1; i <= 6; i++) {
        await db
            .into(db.songs)
            .insert(
              Song.fromBankApiJson({
                'uuid': 'song-s$i',
                'title': 'Song S$i',
                'lyrics': 'S$i lyrics',
                'lyricsFormat': 'opensong',
                'variation_of': i == 1 ? 'song-t' : 'song-s${i - 1}',
              }, sourceBank: bank),
              mode: InsertMode.insertOrReplace,
            );
      }

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      expect(task.errorCount, 1);

      final bankAfterRun = await bankByUuid(bank.uuid);
      expect(
        bankAfterRun.failedProtoSongs.map((failed) => failed.uuid),
        equals(['song-s6']),
      );
      expect(bankAfterRun.failedProtoSongs.single.title, equals('Song S6'));
      expect(bankAfterRun.lastUpdated, isNotNull);
      expect(bankAfterRun.lastUpdated!.isAfter(DateTime(1900)), isTrue);
    });

    test('corrupt ownership fails alone and the run still completes', () async {
      final bank = await insertBank();
      await db
          .into(db.songs)
          .insert(
            Song.fromBankApiJson({
              'uuid': 'song-p',
              'title': 'Song P',
              'lyrics': 'P lyrics',
              'lyricsFormat': 'opensong',
              'variation_of': 'song-t',
            }, sourceBank: bank),
            mode: InsertMode.insertOrReplace,
          );
      await db.customStatement(
        "UPDATE songs SET ownership = 'not-json' WHERE uuid = 'song-p'",
      );

      mockSync(
        listedJson: '[{"uuid":"song-t","title":"Song T"}]',
        detailJson:
            '[{"uuid":"song-t","title":"Song T","lyrics":"T lyrics",'
            '"lyrics_format":"opensong","composer":"New Composer"}]',
      );

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      expect(task.totalCount, 2);
      expect(task.doneCount, 1);
      expect(task.errorCount, 1);
      expect(task.doneCount + task.errorCount, task.totalCount);

      final bankAfterRun = await bankByUuid(bank.uuid);
      expect(
        bankAfterRun.failedProtoSongs.map((failed) => failed.uuid),
        contains('song-p'),
      );
      expect(
        bankAfterRun.failedProtoSongs.singleWhere(
          (failed) => failed.uuid == 'song-p',
        ).title,
        equals('Song P'),
      );
      expect(bankAfterRun.lastUpdated, isNotNull);

      final t = await songByUuid('song-t');
      expect(t.contentMap['composer'], equals('New Composer'));
      final rawOwnership =
          await db
              .customSelect(
                "SELECT ownership FROM songs WHERE uuid = 'song-p'",
              )
              .getSingle();
      expect(rawOwnership.data['ownership'], equals('not-json'));
    });

    test('merge handles over a thousand variation children of one song', () async {
      final bank = await insertBank();

      final childUuids = List.generate(1001, (i) => 'song-c${i + 1}');
      dio.httpClientAdapter = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-t","title":"Song T"}]',
              200,
            );
          }

          if (options.path.contains('/song/song-t')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-t","title":"Song T","lyrics":"T lyrics",'
              '"lyrics_format":"opensong","composer":"New Composer"}]',
              200,
            );
          }

          if (options.path.contains('/song/')) {
            final uuid = options.path.split('/').last;
            return ResponseBody.fromString(
              jsonEncode([
                {
                  'uuid': uuid,
                  'title': uuid,
                  'lyrics': 'Child lyrics',
                  'lyrics_format': 'opensong',
                  'variation_of': 'song-t',
                },
              ]),
              200,
            );
          }

          return ResponseBody.fromString('[]', 200);
        },
      );

      await db.batch((batch) {
        for (final uuid in childUuids) {
          batch.insert(
            db.songs,
            Song.fromBankApiJson({
              'uuid': uuid,
              'title': uuid,
              'lyrics': 'Child lyrics',
              'lyricsFormat': 'opensong',
              'variation_of': 'song-t',
            }, sourceBank: bank),
            mode: InsertMode.insertOrReplace,
          );
        }
      });

      final task = BankSongUpdateTask(bank: bank, dio: dio);
      await task.run();

      expect(task.totalCount, 1002);
      expect(task.doneCount, 1002);
      expect(task.errorCount, 0);
      expect(task.doneCount + task.errorCount, task.totalCount);

      final first = await songByUuid(childUuids.first);
      expect(first.contentMap['composer'], equals('New Composer'));
      final last = await songByUuid(childUuids.last);
      expect(last.contentMap['composer'], equals('New Composer'));
    });
  });
}
