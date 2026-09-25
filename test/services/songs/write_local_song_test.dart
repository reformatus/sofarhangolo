import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/lyrics/format.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/song_link.dart';
import 'package:sofarhangolo/services/assets/write_song_asset.dart';
import 'package:sofarhangolo/services/bank/banks.dart';
import 'package:sofarhangolo/services/songs/original_status.dart';
import 'package:sofarhangolo/services/songs/write_song.dart';

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
            baseUrl: Value(Uri.parse('https://example.com/api')),
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

  Song bankSong(
    String uuid, {
    Map<String, String> contentMap = const {},
    String? lyrics,
    String? variationOf,
  }) {
    return Song(
      uuid: uuid,
      title: 'Song $uuid',
      lyrics: lyrics,
      keyField: const [],
      contentMap: Map.of(contentMap),
      lyricsFormat: LyricsFormat.opensong,
      sourceBank: bank.uuid,
      variationOf: variationOf,
    );
  }

  Future<Song> storedSong(String uuid) =>
      (db.songs.select()..where((s) => s.uuid.equals(uuid))).getSingle();

  Future<SongLink?> copyLinkOf(String localUuid) =>
      (db.songLinks.select()
            ..where(
              (l) =>
                  l.sourceUuid.equals(localUuid) &
                  l.type.equals(SongLinkType.localCopyOf.index),
            ))
          .getSingleOrNull();

  group('writeLocalSong', () {
    test('inserts a new song into the local bank', () async {
      final song = await writeLocalSong(
        Song.local(title: 'Én dal', lyrics: '<song/>'),
      );

      final stored = await storedSong(song.uuid);
      expect(stored.sourceBank, localBankUuid);
      expect(stored.title, 'Én dal');

      final local = await localBank();
      expect(local.access, BankAccess.local);
    });

    test('reuses the row when the uuid already exists', () async {
      final song = await writeLocalSong(
        Song.local(title: 'Első cím', lyrics: 'első'),
      );

      final updated = await writeLocalSong(
        song.copyWith(title: 'Második cím', lyrics: 'második'),
      );

      expect(updated.uuid, song.uuid);
      expect(await db.songs.select().get(), hasLength(1));
      expect((await storedSong(song.uuid)).title, 'Második cím');
    });

    test('rejects songs that belong to another bank', () {
      expect(
        () => writeLocalSong(bankSong('foreign')),
        throwsArgumentError,
      );
    });
  });

  group('copySongToLocal', () {
    test('creates an editable copy in the local bank', () async {
      final original = bankSong(
        'orig-1',
        contentMap: {'svg': 'orig.svg', 'lyrics': 'orig-lyrics'},
        variationOf: 'parent',
      );
      await db.into(db.songs).insert(original);

      final copy = await copySongToLocal(original);
      final stored = await storedSong(copy.uuid);

      expect(copy.uuid, isNot(original.uuid));
      expect(stored.sourceBank, localBankUuid);
      expect(stored.title, original.title);
      expect(stored.lyrics, original.lyrics);
      // Asset views must not fetch the original's bank assets.
      expect(stored.contentMap, isNot(contains('svg')));
      // Bank updates must not treat the copy as a variation of the original.
      expect(stored.variationOf, isNull);
    });

    test('records the original and its content hash in a link', () async {
      final original = bankSong('orig-2', lyrics: '<song><lyrics>a</lyrics></song>');
      await db.into(db.songs).insert(original);

      final copy = await copySongToLocal(original);
      final link = await copyLinkOf(copy.uuid);

      expect(link, isNotNull);
      expect(link!.targetUuid, original.uuid);
      expect(link.targetContentHash, original.contentHash);
    });
  });

  group('originalSongStatus', () {
    test('is null for songs without a localCopyOf link', () async {
      final original = bankSong('orig-3');
      await db.into(db.songs).insert(original);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(originalSongStatusProvider(original).future),
        isNull,
      );
    });

    test('is unchanged while the original content matches', () async {
      final original = bankSong('orig-4', lyrics: '<song/>');
      await db.into(db.songs).insert(original);
      final copy = await copySongToLocal(original);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(originalSongStatusProvider(copy).future),
        OriginalSongStatus.unchanged,
      );
    });

    test('is changed after the original song was updated', () async {
      final original = bankSong('orig-5', lyrics: '<song><lyrics>a</lyrics></song>');
      await db.into(db.songs).insert(original);
      final copy = await copySongToLocal(original);

      await (db.songs.update()..where((s) => s.uuid.equals(original.uuid)))
          .write(SongsCompanion(lyrics: Value('<song><lyrics>b</lyrics></song>')));
      final updated = await storedSong(original.uuid);
      expect(updated.contentHash, isNot(original.contentHash));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(originalSongStatusProvider(copy).future),
        OriginalSongStatus.changed,
      );
    });

    test('is missing when the original song no longer exists', () async {
      final original = bankSong('orig-6');
      await db.into(db.songs).insert(original);
      final copy = await copySongToLocal(original);

      await (db.songs.delete()..where((s) => s.uuid.equals(original.uuid))).go();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(originalSongStatusProvider(copy).future),
        OriginalSongStatus.missing,
      );
    });
  });

  group('contentHash', () {
    test('is independent of contentMap key order', () {
      final a = bankSong('hash-a', contentMap: {'b': '2', 'a': '1'});
      final b = bankSong('hash-a', contentMap: {'a': '1', 'b': '2'});

      expect(a.contentHash, b.contentHash);
    });

    test('changes when lyrics change', () {
      final a = bankSong('hash-b', lyrics: 'első');
      final b = bankSong('hash-b', lyrics: 'második');

      expect(a.contentHash, isNot(b.contentHash));
    });
  });

  group('deleteLocalSong', () {
    test('removes the song, its links and its assets', () async {
      final original = bankSong('orig-7');
      await db.into(db.songs).insert(original);
      final copy = await copySongToLocal(original);
      await writeLocalSongAsset(copy, 'pdf', Uint8List.fromList([1, 2, 3]));
      expect(await copyLinkOf(copy.uuid), isNotNull);

      await deleteLocalSong(copy);

      expect(
        await (db.songs.select()..where((s) => s.uuid.equals(copy.uuid))).get(),
        isEmpty,
      );
      expect(await copyLinkOf(copy.uuid), isNull);
      expect(
        await (db.assets.select()
              ..where((a) => a.songUuid.equals(copy.uuid)))
            .get(),
        isEmpty,
      );
      // The original bank song stays untouched.
      expect(await storedSong(original.uuid).then((s) => s.uuid), original.uuid);
    });
  });

  group('writeLocalSongAsset', () {
    test('stores the asset and points the field at it', () async {
      final song = await writeLocalSong(Song.local(title: 'Kottás dal'));

      await writeLocalSongAsset(song, 'pdf', Uint8List.fromList([9, 9]));

      final stored = await storedSong(song.uuid);
      final reference = stored.contentMap['pdf'];
      expect(reference, startsWith('local://'));

      final assets = await db.assets.select().get();
      expect(assets, hasLength(1));
      expect(assets.single.sourceUrl, reference);
      expect(assets.single.content, Uint8List.fromList([9, 9]));
    });

    test('replaces the previous asset of the same field', () async {
      final song = await writeLocalSong(Song.local(title: 'Csere dal'));

      await writeLocalSongAsset(song, 'pdf', Uint8List.fromList([1]));
      await writeLocalSongAsset(song, 'pdf', Uint8List.fromList([2]));

      final assets = await db.assets.select().get();
      expect(assets, hasLength(1));
      expect(assets.single.content, Uint8List.fromList([2]));

      final stored = await storedSong(song.uuid);
      expect(stored.contentMap['pdf'], assets.single.sourceUrl);
    });
  });
}
