import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/song/song_content.dart';

import '../../harness/test_database.dart';

void main() {
  late LyricDatabase testDb;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    addTearDown(testDb.close);
  });

  Song song(String uuid, String title) =>
      Song.fromBankApiJson({'uuid': uuid, 'title': title});

  test('emits the song and re-emits content changes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await db.into(db.songs).insert(song('s1', 'Első'));

    final titles = <String>[];
    container.listen<AsyncValue<SongSnapshot?>>(songContentProvider('s1'), (
      previous,
      next,
    ) {
      if (next.hasValue && next.value != null) {
        titles.add(next.value!.song.title);
      }
    }, fireImmediately: true);

    await pumpEventQueue();
    expect(titles, contains('Első'));

    await (db.update(db.songs)..where((s) => s.uuid.equals('s1'))).write(
      const SongsCompanion(title: Value('Második')),
    );

    await pumpEventQueue();
    // The equal-uuid-but-changed-content emission must be observed.
    expect(titles.last, 'Második');
  });

  test('emits null when the song does not exist', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final values = <SongSnapshot?>[];
    container.listen<AsyncValue<SongSnapshot?>>(
      songContentProvider('absent'),
      (previous, next) {
        if (next.hasValue) values.add(next.value);
      },
      fireImmediately: true,
    );

    await pumpEventQueue();
    expect(values, isNotEmpty);
    expect(values.last, isNull);
  });
}
