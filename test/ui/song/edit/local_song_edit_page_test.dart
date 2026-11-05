import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/assets/write_song_asset.dart';
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

  /// Inserts a bank song and makes a local copy linked back to it. Returns
  /// both so a test can mutate the original to drive the copy's status:
  /// editing its content makes it `changed`, deleting it makes it `missing`.
  Future<({Song original, Song copy})> makeCopyOfBankSong() async {
    final original = Song(
      uuid: 'bank-original',
      title: 'A banki dal',
      lyrics: '<song><lyrics>a</lyrics></song>',
      keyField: const [],
      contentMap: const {},
      sourceBank: 'bank-x',
    );
    await db.into(db.songs).insert(original);
    final copy = await copySongToLocal(original);
    return (original: original, copy: copy);
  }

  testWidgets('leaving a malformed editor normalizes and saves it', (
    tester,
  ) async {
    final song = await createLocalSong(
      Song.local(title: 'Helyi dal', lyrics: '[V1]\nHello\n.C G'),
    );

    final router = buildRouter();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/song/local/${song.uuid}');
    await tester.pumpAndSettle();

    // The malformed row is called out…
    expect(find.text('Hibás OpenSong formátum'), findsOneWidget);

    // …and leaving the editor adds the missing leading space without tripping
    // the page's autosave listener (which is live during the editor's dispose).
    router.go('/bank');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final saved = (await dbSongFromUuid(song.uuid))!;
    expect(saved.lyrics, contains('\n Hello'));
  });

  testWidgets('hides the original-song card for an unchanged copy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final songs = await makeCopyOfBankSong();
    await pumpApp(tester);

    tester
        .element(find.text('bank-page-marker'))
        .push('/song/local/${songs.copy.uuid}');
    await tester.pumpAndSettle();

    expect(find.byType(LocalSongEditor), findsOneWidget);
    // An unchanged copy has nothing to report: the card (and its noise-y
    // "Nem változott." status) must be gone entirely.
    expect(find.text('Eredeti dal'), findsNothing);
    expect(find.textContaining('Nem változott.'), findsNothing);
  });

  testWidgets('shows the original-song card when the original changed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final songs = await makeCopyOfBankSong();
    // Edit the original's content so its hash drifts from the copy's link.
    await (db.songs.update()..where((s) => s.uuid.equals(songs.original.uuid)))
        .write(
          SongsCompanion(lyrics: Value('<song><lyrics>b</lyrics></song>')),
        );

    await pumpApp(tester);
    tester
        .element(find.text('bank-page-marker'))
        .push('/song/local/${songs.copy.uuid}');
    await tester.pumpAndSettle();

    expect(find.text('Eredeti dal'), findsOneWidget);
    expect(find.textContaining('Megváltozott a másolás óta.'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Eredeti megtekintése'),
      findsOneWidget,
    );
  });

  testWidgets('shows the original-song card when the original is missing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final songs = await makeCopyOfBankSong();
    await (db.songs.delete()..where((s) => s.uuid.equals(songs.original.uuid)))
        .go();

    await pumpApp(tester);
    tester
        .element(find.text('bank-page-marker'))
        .push('/song/local/${songs.copy.uuid}');
    await tester.pumpAndSettle();

    expect(find.text('Eredeti dal'), findsOneWidget);
    expect(
      find.textContaining('Az eredeti dal már nincs meg.'),
      findsOneWidget,
    );
    // A deleted original cannot be opened.
    expect(find.text('Eredeti megtekintése'), findsNothing);
  });

  testWidgets('deleting a song returns to the songs list, not its page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final song = await createLocalSong(Song.local(title: 'Törlendő dal'));
    await pumpApp(tester);

    // Open the editor the usual way: song page, editor on top of it.
    tester.element(find.text('bank-page-marker')).push('/song/${song.uuid}');
    await tester.pumpAndSettle();
    tester
        .element(find.text('song-page-${song.uuid}'))
        .push('/song/local/${song.uuid}');
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

    final song = await createLocalSong(Song.local(title: 'Maradó dal'));
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

  testWidgets(
    'an attachment written while editing survives the next autosave',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final song = await createLocalSong(Song.local(title: 'Kottás dal'));
      await pumpApp(tester);
      tester
          .element(find.text('bank-page-marker'))
          .push('/song/local/${song.uuid}');
      await tester.pumpAndSettle();

      // Attach out of band (the file picker cannot be driven in tests); the
      // editor still holds its stale copy of the song.
      await writeLocalSongAsset(song.uuid, 'svg', Uint8List.fromList([1, 2]));

      expect(find.widgetWithText(TextField, 'Kottás dal'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Kottás dal'),
        'Új cím',
      );
      // Let the debounce fire, then give the real database I/O time to finish.
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      final saved = (await tester.runAsync(() => dbSongFromUuid(song.uuid)))!;
      expect(saved.title, 'Új cím');
      expect(saved.contentMap['svg'], startsWith('local://'));
    },
  );
}
