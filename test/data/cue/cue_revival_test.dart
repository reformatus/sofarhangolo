import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/ui/song/state.dart';

import '../../harness/test_database.dart';

void main() {
  late LyricDatabase testDb;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    addTearDown(testDb.close);
  });

  Future<void> insertSong(String uuid, String title) {
    return db
        .into(db.songs)
        .insert(Song.fromBankApiJson({'uuid': uuid, 'title': title}));
  }

  Map<String, dynamic> songSlideJson(String slideUuid, String songUuid) => {
    'slideType': 'song',
    'uuid': slideUuid,
    'song': {'uuid': songUuid},
    'viewType': 'lyrics',
  };

  test('a slide pointing at a missing song does not abort the cue', () async {
    await insertSong('song-1', 'Megvan');

    final cue = Cue(1, 'cue-1', 'C', 'D', currentCueVersion, [
      songSlideJson('slide-1', 'song-1'),
      songSlideJson('slide-2', 'missing-song'),
    ]);

    final slides = await cue.getRevivedSlides();

    expect(slides, hasLength(2));
    final present = slides[0] as SongSlide;
    final missing = slides[1] as SongSlide;
    expect(present.isMissing, isFalse);
    expect(present.title, 'Megvan');
    expect(missing.isMissing, isTrue);
    expect(missing.songUuid, 'missing-song');
    expect(missing.song, isNull);
  });

  test('an unknown stored view type falls back instead of aborting', () async {
    final cue = Cue(1, 'cue-1', 'C', 'D', currentCueVersion, [
      {...songSlideJson('slide-1', 'missing-song'), 'viewType': 'bogus'},
    ]);

    final slides = await cue.getRevivedSlides();

    final slide = slides.single as SongSlide;
    expect(slide.viewType, SongViewType.lyrics);
    expect(slide.isMissing, isTrue);
  });

  test('a missing-song slide survives serialization round-trip', () async {
    final cue = Cue(1, 'cue-1', 'C', 'D', currentCueVersion, [
      {
        ...songSlideJson('slide-1', 'missing-song'),
        'song': {'uuid': 'missing-song', 'contentHash': 'abc'},
        'title': 'Eltűnt dal',
      },
    ]);

    await cue.getRevivedSlides();

    final content = cue.content.single;
    expect(content['song']['uuid'], 'missing-song');
    expect(content['song']['contentHash'], 'abc');
    expect(content['title'], 'Eltűnt dal');
  });

  test('a malformed slide becomes an unknown slide, not a crash', () async {
    final cue = Cue(1, 'cue-1', 'C', 'D', currentCueVersion, [
      {'slideType': 'song', 'uuid': 'slide-1'}, // no song payload
    ]);

    final slides = await cue.getRevivedSlides();

    expect(slides, hasLength(1));
    expect(slides.single, isA<SongSlide>());
    expect((slides.single as SongSlide).isMissing, isTrue);
  });
}
