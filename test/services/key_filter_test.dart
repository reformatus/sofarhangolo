import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/key/filter.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/key/state.dart';

import '../harness/test_database.dart';
import '../harness/test_harness.dart' show waitForProviderValue;

Song _song(String uuid, String title, List<String> keys) {
  return Song.fromBankApiJson({
    'uuid': uuid,
    'title': title,
    'lyrics': '[V1]\n Hello $title',
    'key': keys,
  });
}

void main() {
  group('key filter selectables', () {
    // The selectable providers query the global `db` directly, so it must be
    // swapped for an in-memory one (see filtered_songs_test for the caveat
    // about the global subquery).
    late LyricDatabase testDb;

    setUpAll(() async {
      testDb = createTestDatabase();
      db = testDb;
      await testDb.customStatement('PRAGMA foreign_keys = OFF');
      await testDb
          .into(testDb.songs)
          .insert(_song('s1', 'Song', ['F-dúr', 'G-moll']));
    });

    tearDownAll(() async {
      await testDb.close();
    });

    test('selectableModes onSelected works after the provider is invalidated', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final selectables = await waitForProviderValue(
        container,
        selectableModesProvider,
      );
      final onSelected = selectables
          .firstWhere((selectable) => selectable.label == 'dúr')
          .onSelected;

      // Simulate the song/bank list changing and rebuilding the provider while
      // a chip built from the previous value is still on screen. Reading the
      // provider again forces the rebuild, which unmounts the Ref the old
      // callbacks captured.
      container.invalidate(selectableModesProvider);
      await waitForProviderValue(container, selectableModesProvider);

      expect(() => onSelected(true), returnsNormally);
      expect(container.read(keyFilterStateProvider).modes, contains('dúr'));
    });

    test(
      'selectablePitches onSelected works after the provider is invalidated',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final selectables = await waitForProviderValue(
          container,
          selectablePitchesProvider,
        );
        final onSelected = selectables
            .firstWhere((selectable) => selectable.label == 'F')
            .onSelected;

        container.invalidate(selectablePitchesProvider);
        await waitForProviderValue(container, selectablePitchesProvider);

        expect(() => onSelected(true), returnsNormally);
        expect(container.read(keyFilterStateProvider).pitches, contains('F'));
      },
    );
  });
}
