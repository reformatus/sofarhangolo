import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/filter.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/key/state.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/multiselect-tags/state.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/search/state.dart';

import '../harness/test_database.dart';
import '../harness/test_harness.dart' show waitForProviderValue;

/// Filter state pinned to fixed values for a test.
class FixedTagsFilterState extends MultiselectTagsFilterState {
  FixedTagsFilterState(this.value);

  final Map<String, List<String>> value;

  @override
  Map<String, List<String>> build() => value;
}

Song _song(String uuid, String title, [Map<String, Object> extra = const {}]) {
  return Song.fromBankApiJson({
    'uuid': uuid,
    'title': title,
    'lyrics': '[V1]\n Hello $title',
    ...extra,
  });
}

void main() {
  group('SongResultsLimit', () {
    test('pages forward and resets when the search changes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(songResultsLimitProvider), songSearchPageSize);

      container.read(songResultsLimitProvider.notifier).loadMore();
      expect(container.read(songResultsLimitProvider), songSearchPageSize * 2);

      container.read(searchStringStateProvider.notifier).set('alma');
      await Future<void>.microtask(() {});

      expect(container.read(songResultsLimitProvider), songSearchPageSize);
    });
  });

  group('filteredSongs content-map filters', () {
    // Shared database for the group: downloadedAssetsSubquery is a global
    // initialized against the first `db` it sees, so per-test databases
    // would leave it pointing at a closed connection.
    late LyricDatabase testDb;

    setUpAll(() async {
      testDb = createTestDatabase();
      db = testDb;
      // Same as songs_update_test: the songs→banks FK is unusable with
      // in-memory schemas, and these tests do not rely on it.
      await testDb.customStatement('PRAGMA foreign_keys = OFF');
      await testDb
          .into(testDb.songs)
          .insert(
            _song('s1', 'Rock song', {
              'genre': ['Rock'],
            }),
          );
      await testDb
          .into(testDb.songs)
          .insert(
            _song('s2', 'Rockballada', {
              'genre': ['Rockballada'],
            }),
          );
      await testDb
          .into(testDb.songs)
          .insert(_song('s3', 'Magyar song', {'language': 'magyar'}));
      // Songs with key fields, for the key-filter parity test.
      await testDb
          .into(testDb.songs)
          .insert(
            _song('k1', 'K1', {
              'key': ['C-dúr'],
            }),
          );
      await testDb
          .into(testDb.songs)
          .insert(
            _song('k2', 'K2', {
              'key': ['A-moll'],
            }),
          );
      await testDb
          .into(testDb.songs)
          .insert(
            _song('k3', 'K3', {
              'key': ['C-dúr', 'A-moll'],
            }),
          );
    });

    tearDownAll(() async {
      await testDb.close();
    });

    Future<Set<String>> uuidsFor(Map<String, List<String>> filters) async {
      final container = ProviderContainer(
        overrides: [
          multiselectTagsFilterStateProvider.overrideWith(
            () => FixedTagsFilterState(filters),
          ),
        ],
      );
      addTearDown(container.dispose);
      final results = await waitForProviderValue(
        container,
        filteredSongsProvider,
      );
      return results.results.map((result) => result.song.uuid).toSet();
    }

    test('list fields match whole elements only', () async {
      // Quoted LIKE: '"Rock"' must not hit '"Rockballada"'.
      expect(
        await uuidsFor({
          'genre': ['Rock'],
        }),
        {'s1'},
      );
    });

    test('text fields match substrings', () async {
      expect(
        await uuidsFor({
          'language': ['gyar'],
        }),
        {'s3'},
      );
    });

    test('values OR within a field', () async {
      expect(
        await uuidsFor({
          'genre': ['Rock', 'Rockballada'],
        }),
        {'s1', 's2'},
      );
    });

    test('different fields AND together', () async {
      // No song has both, so the intersection is empty.
      expect(
        await uuidsFor({
          'genre': ['Rock'],
          'language': ['gyar'],
        }),
        isEmpty,
      );
    });

    // Shares this group's database: downloadedAssetsSubquery is global.
    const noKeyFilters = (
      pitches: <String>{},
      modes: <String>{},
      keys: <KeyField>{},
    );

    Future<SongResultPage> pageResult({
      int limit = 100,
      KeyFilters keyFilters = noKeyFilters,
    }) => filteredSongsPage(
      filters: const {},
      bankFilters: const {},
      keyFilters: keyFilters,
      limit: limit,
    ).first;

    Future<List<SongResult>> page({
      int limit = 100,
      KeyFilters keyFilters = noKeyFilters,
    }) => pageResult(
      limit: limit,
      keyFilters: keyFilters,
    ).then((result) => result.results);

    test('is paginated and ordered by folded title', () async {
      final all = await page();
      expect(all, hasLength(6));

      final firstPage = await page(limit: 2);
      expect(firstPage, hasLength(2));
      // A page is a prefix of the full, deterministically ordered listing.
      expect(
        firstPage.map((r) => r.song.uuid),
        all.take(2).map((r) => r.song.uuid),
      );
      // The window count still reports the whole match set, not the page.
      expect((await pageResult(limit: 2)).total, 6);
    });

    test('SQL key filter mirrors matchesKeyFilters', () async {
      final songs = await (db.select(db.songs)).get();
      final cases = <KeyFilters>[
        (pitches: {'C'}, modes: <String>{}, keys: <KeyField>{}),
        (pitches: <String>{}, modes: {'moll'}, keys: <KeyField>{}),
        (pitches: {'C'}, modes: {'moll'}, keys: <KeyField>{}),
        (pitches: {'A'}, modes: {'moll'}, keys: <KeyField>{}),
        (pitches: <String>{}, modes: <String>{}, keys: {KeyField('C', 'dúr')}),
      ];

      for (final keyFilters in cases) {
        final expected = songs
            .where((song) => matchesKeyFilters(song, keyFilters))
            .map((song) => song.uuid)
            .toSet();
        final actual = (await page(keyFilters: keyFilters))
            .map((r) => r.song.uuid)
            .toSet();
        expect(actual, expected, reason: 'key filter $keyFilters');
        expect(
          (await pageResult(keyFilters: keyFilters)).total,
          expected.length,
          reason: 'total for key filter $keyFilters',
        );
      }
    });
  });
}
