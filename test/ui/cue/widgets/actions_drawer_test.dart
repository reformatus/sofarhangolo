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
import 'package:sofarhangolo/ui/common/sidebar/sidebar.dart';

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

    // The swap action is part of the hint box, not a button sitting under it.
    final hintBox = tester.getRect(
      find.ancestor(
        of: find.text('Helyi másolat'),
        matching: find.byType(Card),
      ),
    );
    final swap = tester.getRect(
      find.widgetWithText(FilledButton, 'Csere a helyi másolatra'),
    );
    expect(hintBox.top, lessThan(swap.top));
    expect(hintBox.bottom, greaterThan(swap.bottom));

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

  testWidgets('drawer buttons fill the sidebar, grouped by meaning', (
    tester,
  ) async {
    final cue = await insertCueHarnessCue(
      cueUuid: 'cue-layout',
      fixtures: const [
        CueSongFixture(
          songUuid: 'song-1',
          slideUuid: 'slide-1',
          title: 'Song 1',
          lyrics: '[V1]\n Alpha line',
        ),
      ],
    );
    await harness.container
        .read(activeCueSessionProvider.notifier)
        .load(cue.uuid);
    await waitForProviderValue(harness.container, activeCueSessionProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 304, height: 900, child: ActionsDrawer()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Every button spans the drawer (minus its own padding).
    final drawer = tester.getRect(find.byType(ActionsDrawer));
    for (final label in ['Ugrás a dalhoz', 'Másolat szerkesztése']) {
      final button = tester.getRect(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
        ),
      );
      expect(button.width, drawer.width - 16, reason: label);
    }

    // The song group (jump/edit) comes above the view group (chooser).
    final jump = tester.getCenter(find.text('Ugrás a dalhoz')).dy;
    final divider = tester.getCenter(find.byType(SidebarDivider)).dy;
    final chooser = tester.getCenter(find.text('Dalszöveg')).dy;
    expect(jump, lessThan(divider));
    expect(divider, lessThan(chooser));
  });

  testWidgets('the view switcher label uses the button it sits on', (
    tester,
  ) async {
    final cue = await insertCueHarnessCue(
      cueUuid: 'cue-dropdown',
      fixtures: const [
        CueSongFixture(
          songUuid: 'song-1',
          slideUuid: 'slide-1',
          title: 'Song 1',
          lyrics: '[V1]\n Alpha line',
        ),
      ],
    );
    await harness.container
        .read(activeCueSessionProvider.notifier)
        .load(cue.uuid);
    await waitForProviderValue(harness.container, activeCueSessionProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 304, height: 900, child: ActionsDrawer()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The dropdown is painted on the filled button's background, so its label
    // must take that button's foreground — not a surface-derived color that
    // only reads well somewhere else.
    final colors = Theme.of(
      tester.element(find.byType(ActionsDrawer)),
    ).colorScheme;
    final label = tester.widget<Text>(find.text('Dalszöveg'));
    expect(label.style?.color, colors.onPrimary);
    expect(label.style?.color, isNot(colors.inverseSurface));
  });
}
