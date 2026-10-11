import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/ui/cue/session/session_provider.dart';
import 'package:sofarhangolo/ui/song/state.dart';

import '../../../harness/test_harness.dart';

void main() {
  late LyricDatabase testDb;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    addTearDown(testDb.close);
  });

  SongSlide currentSlide(ProviderContainer container) =>
      container.read(activeCueSessionProvider).value!.slides.single
          as SongSlide;

  test('refreshes cached slide content when the song changes', () async {
    final song = Song.fromBankApiJson({
      'uuid': 'song-1',
      'title': 'Régi cím',
      'lyrics': 'Szent vagy',
    });
    await db.into(db.songs).insert(song);

    final slide = SongSlide.from(song, viewType: SongViewType.lyrics);
    await db
        .into(db.cues)
        .insert(
          Cue(1, 'cue-1', 'C', 'D', currentCueVersion, [
            Map<String, dynamic>.from(slide.toJson()),
          ]),
        );

    final container = createTestContainer();
    addTearDown(container.dispose);

    await container.read(activeCueSessionProvider.notifier).load('cue-1');
    await pumpEventQueue();

    expect(currentSlide(container).title, 'Régi cím');

    await (db.update(db.songs)..where((s) => s.uuid.equals('song-1'))).write(
      const SongsCompanion(title: Value('Új cím')),
    );
    await pumpEventQueue();

    // The session's cached snapshot must reflect the new content.
    expect(currentSlide(container).title, 'Új cím');
    expect(currentSlide(container).song, isNotNull);
  });

  test('transitions a slide to missing when its song is deleted', () async {
    final song = Song.fromBankApiJson({'uuid': 'song-1', 'title': 'Megvan'});
    await db.into(db.songs).insert(song);

    final slide = SongSlide.from(song, viewType: SongViewType.lyrics);
    await db
        .into(db.cues)
        .insert(
          Cue(1, 'cue-1', 'C', 'D', currentCueVersion, [
            Map<String, dynamic>.from(slide.toJson()),
          ]),
        );

    final container = createTestContainer();
    addTearDown(container.dispose);

    await container.read(activeCueSessionProvider.notifier).load('cue-1');
    await pumpEventQueue();

    expect(currentSlide(container).isMissing, isFalse);

    await (db.delete(db.songs)..where((s) => s.uuid.equals('song-1'))).go();
    await pumpEventQueue();

    expect(currentSlide(container).isMissing, isTrue);
    expect(currentSlide(container).songUuid, 'song-1');
  });
}
