import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/filter.dart';
import 'package:sofarhangolo/services/songs/search_index.dart';

import '../harness/test_database.dart';

/// `songs_fts` is derived data, so the app heals a corrupt index instead of
/// leaving a dead error card on screen.
///
/// The damage the tests reproduce is what the old write path left behind: an
/// index row whose song is gone. `bm25()` never reads the content table, so it
/// looks fine; `snippet()` does, and the search materialises the hits, so every
/// matched row asks for one.
void main() {
  // Shared database: searchSongs reads through downloadedAssetsSubquery, a
  // global initialized against the first `db` it sees.
  late LyricDatabase testDb;

  setUpAll(() async {
    testDb = createTestDatabase();
    db = testDb;
    // Same as songs_update_test: the songs→banks FK is unusable with in-memory
    // schemas, and these tests do not rely on it.
    await testDb.customStatement('PRAGMA foreign_keys = OFF');
  });

  tearDownAll(() async {
    await testDb.close();
  });

  setUp(() async {
    // Every test starts from an empty, consistent index. The delete goes
    // through the triggers, and the rebuild drops the orphan rows a previous
    // test injected.
    await testDb.delete(testDb.songs).go();
    await rebuildSearchIndex();
  });

  Song song(String uuid, String title) => Song(
    uuid: uuid,
    title: title,
    lyrics: '$title szövege',
    keyField: const [],
    contentMap: const {},
  );

  Future<void> insert(Iterable<Song> songs) =>
      testDb.batch((batch) => batch.insertAll(testDb.songs, songs));

  /// An index row no song backs - the state a REPLACE-style upsert leaves
  /// behind, since its implicit delete skips the DELETE triggers.
  Future<void> orphanIndexRow(int rowid, String text) => testDb.customStatement(
    "INSERT INTO songs_fts(rowid, title, lyrics) VALUES (?, ?, '')",
    [rowid, text],
  );

  /// FTS5's `integrity-check` with `rank` also compares the index against the
  /// content table - the part the plain check skips, and the part that breaks.
  Future<void> expectIndexConsistent() async {
    await expectLater(
      testDb.customStatement(
        "INSERT INTO songs_fts(songs_fts, rank) VALUES('integrity-check', 1)",
      ),
      completes,
    );
  }

  Future<List<String>> searchTitles(String term) async {
    final page = await searchSongs(
      searchString: term,
      searchFields: const [],
      filters: const {},
      bankFilters: const {},
      keyFilters: noKeyFilters,
      limit: 50,
    ).first;
    return [for (final result in page.results) result.song.title];
  }

  group('search index repair', () {
    test('a search that hits an orphaned index row repairs it', () async {
      await insert([song('a', 'Alma dal'), song('b', 'Almafa virág')]);
      await orphanIndexRow(999999, 'Alma régi');

      // Without the repair this streams a SqliteException(267).
      expect(
        await searchTitles('alma'),
        containsAll(<String>['Alma dal', 'Almafa virág']),
      );
      await expectIndexConsistent();
    });

    test('the rebuilt index is complete, not just readable', () async {
      await insert([song('a', 'Alma dal')]);
      await orphanIndexRow(999999, 'Alma régi');

      await searchTitles('alma');

      // The orphan's text is gone with it: only the song matches any more.
      expect(await searchTitles('régi'), isEmpty);
      expect(await searchTitles('alma'), ['Alma dal']);
    });

    test('a healthy index is left alone', () async {
      await insert([song('a', 'Alma dal')]);

      expect(await searchTitles('alma'), ['Alma dal']);
      await expectIndexConsistent();
    });

    test('a stream that already produced a value is not re-run', () async {
      var runs = 0;
      Stream<int> source() {
        runs++;
        return () async* {
          yield 1;
          throw SqliteException(
            extendedResultCode: 267,
            message: 'database disk image is malformed',
          );
        }();
      }

      await expectLater(
        withSearchIndexRepair(source),
        emitsInOrder([1, emitsError(isA<SqliteException>())]),
      );
      // Re-running it would have repeated the value.
      expect(runs, 1);
    });

    test('errors that are not index corruption pass through', () async {
      final failure = SqliteException(
        extendedResultCode: 1,
        message: 'no such table: songs_fts',
      );

      await expectLater(
        withSearchIndexRepair<int>(() => Stream.error(failure)),
        emitsError(same(failure)),
      );
    });

    test('classifies corruption, not every SQL error', () {
      expect(
        isSearchIndexCorruption(
          SqliteException(
            extendedResultCode: 267,
            message: 'database disk image is malformed',
          ),
        ),
        isTrue,
      );
      expect(
        isSearchIndexCorruption(
          SqliteException(
            extendedResultCode: 11,
            message: 'database disk image is malformed',
          ),
        ),
        isTrue,
      );
      // Some executors hand the error over without the type.
      expect(
        isSearchIndexCorruption(Exception('database disk image is malformed')),
        isTrue,
      );
      expect(
        isSearchIndexCorruption(
          SqliteException(extendedResultCode: 1, message: 'no such table'),
        ),
        isFalse,
      );
      expect(isSearchIndexCorruption(StateError('nope')), isFalse);
    });
  });
}
