import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/services/song/from_uuid.dart';
import 'package:sofarhangolo/services/songs/write_song.dart';

import '../../../harness/cue_widget_harness.dart';
import '../../../harness/test_harness.dart';

void main() {
  late LyricDatabase testDb;
  late TestHarness harness;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    harness = TestHarness();
  });

  tearDown(() async {
    harness.dispose();
    await testDb.close();
  });

  testWidgets('bank slide with a local copy offers to swap to it', (
    tester,
  ) async {
    final cue = await insertCueHarnessCue(
      cueUuid: 'cue-copy',
      fixtures: const [
        CueSongFixture(
          songUuid: 'song-1',
          slideUuid: 'slide-1',
          title: 'Song 1',
          lyrics: '[V1]\n Alpha line',
        ),
      ],
    );

    final bankSong = (await dbSongFromUuid('song-1'))!;
    final copy = await copySongToLocal(bankSong);

    final cueHarness = await pumpCueWidgetHarness(
      tester,
      testHarness: harness,
      cueUuid: cue.uuid,
    );

    expect(find.text('Helyi másolat'), findsOneWidget);
    expect(find.text('Csere a helyi másolatra'), findsOneWidget);

    await tester.tap(find.text('Csere a helyi másolatra'));
    await tester.pumpAndSettle();

    expect(cueHarness.currentSongSlide.songUuid, copy.uuid);
    // Once the slide uses the copy, the hint is gone.
    expect(find.text('Helyi másolat'), findsNothing);

    // Let the debounced cue write finish so no timer outlives the test.
    await cueHarness.flushWrites();
  });

  testWidgets('bank slide without a copy shows no swap hint', (tester) async {
    final cue = await insertCueHarnessCue(
      cueUuid: 'cue-no-copy',
      fixtures: const [
        CueSongFixture(
          songUuid: 'song-1',
          slideUuid: 'slide-1',
          title: 'Song 1',
          lyrics: '[V1]\n Alpha line',
        ),
      ],
    );

    await pumpCueWidgetHarness(
      tester,
      testHarness: harness,
      cueUuid: cue.uuid,
    );

    expect(find.text('Helyi másolat'), findsNothing);
  });
}
