import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/assets/get_song_asset.dart';
import 'package:sofarhangolo/services/bank/banks.dart';
import 'package:sofarhangolo/services/error/app_error.dart';
import 'package:sofarhangolo/services/http/dio_provider.dart';

import '../../harness/test_harness.dart';

void main() {
  late LyricDatabase testDb;
  late Bank bank;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    bank = await db
        .into(db.banks)
        .insertReturning(
          BanksCompanion.insert(
            uuid: 'bank-1',
            name: 'Test Bank',
            baseUrl: Value(Uri.parse('https://example.com/')),
            parallelUpdateJobs: 1,
            amountOfSongsInRequest: 1,
            noCms: false,
            songFields: {},
            isEnabled: true,
            isOfflineMode: false,
          ),
        );
  });

  tearDown(() async {
    await testDb.close();
  });

  Song bankSong({Map<String, Object> contentMap = const {'pdf': 'song.pdf'}}) {
    return Song(
      uuid: 'song-1',
      title: 'Dal',
      keyField: const [],
      contentMap: Map.of(contentMap),
      sourceBank: bank.uuid,
    );
  }

  Dio dioReturning(List<int> bytes, {List<RequestOptions>? record}) {
    final dio = createMockDio();
    dio.httpClientAdapter = MockHttpAdapter(
      onRequest: (options) {
        record?.add(options);
        return ResponseBody.fromBytes(bytes, 200);
      },
    );
    return dio;
  }

  group('fetchSongAsset', () {
    test('returns null when the song has no such attachment', () async {
      final song = bankSong(contentMap: const {});
      expect(await fetchSongAsset(song, 'pdf', dio: createMockDio()), isNull);
    });

    test('downloads and caches a bank attachment', () async {
      final song = bankSong();
      await db.into(db.songs).insert(song);
      final requests = <RequestOptions>[];

      final bytes = await fetchSongAsset(
        song,
        'pdf',
        dio: dioReturning([1, 2, 3], record: requests),
      );

      expect(bytes, Uint8List.fromList([1, 2, 3]));
      expect(requests, hasLength(1));
      expect(requests.single.uri.toString(), 'https://example.com/song.pdf');

      final assets = await db.assets.select().get();
      expect(assets, hasLength(1));
      expect(assets.single.sourceUrl, 'https://example.com/song.pdf');
      expect(assets.single.content, Uint8List.fromList([1, 2, 3]));
    });

    test('serves a second fetch from the cache with no request', () async {
      final song = bankSong();
      await db.into(db.songs).insert(song);
      final requests = <RequestOptions>[];
      final dio = dioReturning([9], record: requests);

      await fetchSongAsset(song, 'pdf', dio: dio);
      final again = await fetchSongAsset(song, 'pdf', dio: dio);

      expect(requests, hasLength(1));
      expect(again, Uint8List.fromList([9]));
    });

    test('resolves a local song attachment from the assets table', () async {
      await localBank();
      final song = Song(
        uuid: 'local-1',
        title: 'Helyi',
        keyField: const [],
        contentMap: const {'pdf': 'local://abc'},
        sourceBank: localBankUuid,
      );
      await db.into(db.songs).insert(song);
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              songUuid: 'local-1',
              fieldName: 'pdf',
              sourceUrl: 'local://abc',
              content: Uint8List.fromList([7]),
            ),
          );

      final bytes = await fetchSongAsset(song, 'pdf', dio: createMockDio());

      expect(bytes, Uint8List.fromList([7]));
    });

    test('surfaces a download failure as an AppError', () async {
      final song = bankSong();
      await db.into(db.songs).insert(song);
      final dio = createMockDio();
      dio.httpClientAdapter = MockHttpAdapter(
        onRequest: (_) => throw DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        fetchSongAsset(song, 'pdf', dio: dio),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('getSongAsset stream', () {
    test('reports a starting progress event then the bytes', () async {
      final song = bankSong();
      await db.into(db.songs).insert(song);

      final container = createTestContainer();
      addTearDown(container.dispose);
      final dio = container.read(dioProvider);
      dio.httpClientAdapter = MockHttpAdapter(
        onRequest: (_) => ResponseBody.fromBytes([4, 5], 200),
      );

      final events = <AssetResult>[];
      final done = Completer<void>();
      final sub = container.listen(
        getSongAssetProvider(song, 'pdf'),
        (previous, next) {
          final event = next.value;
          if (event == null) return;
          events.add(event);
          if (event.data != null && !done.isCompleted) done.complete();
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await done.future.timeout(const Duration(seconds: 5));

      // First event marks the start of the download (no bytes yet)...
      expect(events.first.progress, isNull);
      expect(events.first.data, isNull);
      // ...and the last carries the bytes.
      expect(events.last.data, Uint8List.fromList([4, 5]));
    });

    test('emits the bytes directly for a cached attachment', () async {
      final song = bankSong();
      await db.into(db.songs).insert(song);
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              songUuid: song.uuid,
              fieldName: 'pdf',
              sourceUrl: 'https://example.com/song.pdf',
              content: Uint8List.fromList([8]),
            ),
          );

      final container = createTestContainer();
      addTearDown(container.dispose);

      final events = <AssetResult>[];
      final done = Completer<void>();
      final sub = container.listen(
        getSongAssetProvider(song, 'pdf'),
        (previous, next) {
          final event = next.value;
          if (event == null) return;
          events.add(event);
          if (event.data != null && !done.isCompleted) done.complete();
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await done.future.timeout(const Duration(seconds: 5));

      expect(events, hasLength(1));
      expect(events.single.data, Uint8List.fromList([8]));
    });
  });
}
