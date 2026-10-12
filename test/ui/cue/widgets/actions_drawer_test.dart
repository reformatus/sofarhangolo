import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/services/song/from_uuid.dart';
import 'package:sofarhangolo/services/songs/original_status.dart';
import 'package:sofarhangolo/services/songs/write_song.dart';
import 'package:sofarhangolo/ui/cue/session/session_provider.dart';
import 'package:sofarhangolo/ui/cue/widgets/actions_drawer.dart';

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

  testWidgets(
    'bank slide: copy-then-edit switches the slide to the new copy',
    (tester) async {
      final cue = await insertCueHarnessCue(
        cueUuid: 'cue-edit',
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

      await harness.container
          .read(activeCueSessionProvider.notifier)
          .load(cue.uuid);
      await waitForProviderValue(harness.container, activeCueSessionProvider);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: SizedBox(width: 280, child: ActionsDrawer()),
            ),
          ),
          GoRoute(
            path: '/song/local/:uuid',
            builder: (context, state) =>
                Scaffold(body: Text('editor:${state.pathParameters['uuid']}')),
          ),
          GoRoute(
            path: '/song/:uuid',
            builder: (context, state) =>
                Scaffold(body: Text('songpage:${state.pathParameters['uuid']}')),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Másolat szerkesztése'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Másolat szerkesztése'),
      );
      await tester.pumpAndSettle();

      final editorLabel = tester
          .widget<Text>(find.textContaining('editor:'))
          .data!;
      final copyUuid = editorLabel.substring('editor:'.length);

      // The slide now points at the freshly created copy…
      final session = harness.container
          .read(activeCueSessionProvider)
          .value!;
      expect((session.currentSlide! as SongSlide).songUuid, copyUuid);
      // …which really is this bank song's copy…
      expect((await localCopyOf(bankSong))?.uuid, copyUuid);
      // …and the cue stays under the editor (no copy page pushed).
      expect(find.textContaining('songpage:'), findsNothing);

      await harness.container
          .read(activeCueSessionProvider.notifier)
          .flushWrites();
    },
  );
}
