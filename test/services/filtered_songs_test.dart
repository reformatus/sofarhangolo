import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/filter.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/multiselect-tags/state.dart';

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
      return results.map((result) => result.song.uuid).toSet();
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
  });
}
