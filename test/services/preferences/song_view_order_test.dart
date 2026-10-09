import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/services/preferences/providers/song_view_order.dart';

import '../../harness/test_database.dart';

void main() {
  late LyricDatabase testDb;

  setUp(() {
    testDb = createTestDatabase();
    db = testDb;
  });

  tearDown(() async {
    await testDb.close();
  });

  Future<ProviderContainer> loadedContainer() async {
    await db
        .into(db.preferenceStorage)
        .insertOnConflictUpdate(
          PreferenceStorageCompanion(
            key: const Value('songViewOrderPreferences'),
            value: Value({
              'songViewOrder': ['svg', 'pdf', 'lyrics', 'chords'],
            }),
          ),
        );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(songViewOrderPreferencesProvider.notifier)
        .loadFromDb();
    return container;
  }

  // ReorderableListView.onReorderItem already adjusts newIndex for the
  // item removed at oldIndex, so newIndex is the entry's final index.
  group('SongViewOrderPreferences.reorder', () {
    test('moves an entry down to its final index', () async {
      final container = await loadedContainer();
      final notifier = container.read(
        songViewOrderPreferencesProvider.notifier,
      );

      notifier.reorder(0, 2); // svg after lyrics

      expect(notifier.state.songViewOrder.map((e) => e.type).toList(), [
        'pdf',
        'lyrics',
        'svg',
        'chords',
      ]);
    });

    test('moves an entry up to its final index', () async {
      final container = await loadedContainer();
      final notifier = container.read(
        songViewOrderPreferencesProvider.notifier,
      );

      notifier.reorder(3, 0); // chords before svg

      expect(notifier.state.songViewOrder.map((e) => e.type).toList(), [
        'chords',
        'svg',
        'pdf',
        'lyrics',
      ]);
    });
  });
}
