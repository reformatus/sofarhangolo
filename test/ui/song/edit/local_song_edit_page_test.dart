import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/song/from_uuid.dart';
import 'package:sofarhangolo/services/songs/write_song.dart';
import 'package:sofarhangolo/ui/song/edit/page.dart';

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

  /// Routes mirroring the app: the songs list below a song page below the
  /// editor, so the test can see where deleting navigates to.
  GoRouter buildRouter() => GoRouter(
    initialLocation: '/bank',
    routes: [
      GoRoute(
        path: '/bank',
        builder: (context, state) =>
            const Scaffold(body: Text('bank-page-marker')),
      ),
      GoRoute(
        path: '/song/:uuid',
        builder: (context, state) =>
            Scaffold(body: Text('song-page-${state.pathParameters['uuid']}')),
      ),
      GoRoute(
        path: '/song/local/:uuid',
        builder: (context, state) =>
            LocalSongEditPage(state.pathParameters['uuid']!),
      ),
    ],
  );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('deleting a song returns to the songs list, not its page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final song = await writeLocalSong(Song.local(title: 'Törlendő dal'));
    await pumpApp(tester);

    // Open the editor the usual way: song page, editor on top of it.
    tester
        .element(find.text('bank-page-marker'))
        .push('/song/${song.uuid}');
    await tester.pumpAndSettle();
    tester.element(find.text('song-page-${song.uuid}')).push(
      '/song/local/${song.uuid}',
    );
    await tester.pumpAndSettle();
    expect(find.byType(LocalSongEditor), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Törlés'));
    await tester.pumpAndSettle();

    // The song is gone from the database.
    expect(await dbSongFromUuid(song.uuid), isNull);
    // We landed on the songs list, not on the deleted song's page.
    expect(find.text('bank-page-marker'), findsOneWidget);
    expect(find.text('song-page-${song.uuid}'), findsNothing);
  });

  testWidgets('cancelling the delete dialog keeps editing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final song = await writeLocalSong(Song.local(title: 'Maradó dal'));
    await pumpApp(tester);

    tester
        .element(find.text('bank-page-marker'))
        .push('/song/local/${song.uuid}');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mégse'));
    await tester.pumpAndSettle();

    expect(find.byType(LocalSongEditor), findsOneWidget);
    expect(await dbSongFromUuid(song.uuid), isNotNull);
  });
}
