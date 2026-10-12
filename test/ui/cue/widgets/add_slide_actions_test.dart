import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/services/song/from_uuid.dart';
import 'package:sofarhangolo/ui/cue/session/session_provider.dart';
import 'package:sofarhangolo/ui/cue/widgets/add_slide_actions.dart';

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

  Future<GoRouter> pumpActions(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: CueAddSlideActions()),
        ),
        GoRoute(
          path: '/song/local/:uuid',
          builder: (context, state) =>
              Scaffold(body: Text('editor:${state.pathParameters['uuid']}')),
        ),
        GoRoute(
          path: '/bank',
          builder: (context, state) =>
              const Scaffold(body: Text('songs-page-marker')),
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
    return router;
  }

  testWidgets('offers both add options as chips', (tester) async {
    await pumpActions(tester);

    expect(find.text('Új dal hozzáadása'), findsOneWidget);
    expect(find.text('Meglévő dal hozzáadása'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(2));
  });

  testWidgets('creating a song appends it to the cue and opens its editor', (
    tester,
  ) async {
    final cue = await insertCueHarnessCue(
      cueUuid: 'cue-add',
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

    await pumpActions(tester);
    await tester.tap(find.text('Új dal hozzáadása'));
    await tester.pumpAndSettle();

    // The editor opened for the new song.
    final editorLabel = tester
        .widget<Text>(find.textContaining('editor:'))
        .data!;
    final newSongUuid = editorLabel.substring('editor:'.length);

    // The new song is a local one, titled and still empty…
    final song = (await dbSongFromUuid(newSongUuid))!;
    expect(song.sourceBank, localBankUuid);
    expect(song.title, 'Új dal');
    expect(song.lyrics ?? '', isEmpty);

    // …appended after the existing slide of the cue.
    final session = harness.container.read(activeCueSessionProvider).value!;
    expect(session.slides, hasLength(2));
    final appended = session.slides.last;
    expect(appended, isA<SongSlide>());
    expect((appended as SongSlide).songUuid, newSongUuid);

    await harness.container
        .read(activeCueSessionProvider.notifier)
        .flushWrites();
  });

  testWidgets('adding an existing song opens the songs page', (tester) async {
    final cue = await insertCueHarnessCue(
      cueUuid: 'cue-existing',
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

    await pumpActions(tester);
    await tester.tap(find.text('Meglévő dal hozzáadása'));
    await tester.pumpAndSettle();

    expect(find.text('songs-page-marker'), findsOneWidget);
    // Nothing was added to the cue just by opening the songs page.
    expect(
      harness.container.read(activeCueSessionProvider).value!.slides,
      hasLength(1),
    );
  });
}
