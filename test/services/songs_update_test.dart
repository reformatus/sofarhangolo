import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofar/data/bank/bank.dart';
import 'package:sofar/data/database.dart';
import 'package:sofar/data/song/song.dart';
import 'package:sofar/services/songs/update.dart';

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

      await updateBankSongs(bank, dio).drain<void>();

      final assets = await db.select(db.assets).get();
      expect(assets, isEmpty);

      final updatedSong =
          await (db.songs.select()..where((s) => s.uuid.equals('song-1')))
              .getSingle();
      expect(updatedSong.contentMap['pdf'], equals('/new.pdf'));
    });

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

      await updateBankSongs(bank, dio).drain<void>();

      final assets = await db.select(db.assets).get();
      expect(assets, hasLength(1));
      expect(assets.first.songUuid, equals('song-2'));
      expect(
        assets.first.sourceUrl,
        equals('https://example.com/api/other.pdf'),
      );
    });

    test('deletes assets even when updated song payload is unchanged', () async {
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

      await updateBankSongs(bank, dio).drain<void>();

      final assets = await db.select(db.assets).get();
      expect(assets, isEmpty);
    });
  });
}
