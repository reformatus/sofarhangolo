import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/connectivity/provider.dart';
import 'package:sofarhangolo/services/song/from_uuid.dart';
import 'package:sofarhangolo/services/songs/bundle/export_bundle.dart';
import 'package:sofarhangolo/services/songs/original_status.dart';
import 'package:sofarhangolo/services/songs/write_song.dart';
import 'package:sofarhangolo/ui/common/import/song_bundle_import.dart';
import 'package:sofarhangolo/ui/common/share/dialog.dart';
import 'package:sofarhangolo/ui/song/edit/page.dart';
import 'package:sofarhangolo/ui/song/widgets/app_bar.dart';

import '../../../harness/test_harness.dart';

class _FakeConnection extends Connection {
  @override
  ConnectionType build() => ConnectionType.unlimited;
}

void main() {
  late LyricDatabase testDb;
  late TestHarness harness;
  late GoRouter router;
  Uint8List? pending;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    harness = TestHarness(
      additionalOverrides: [
        connectionProvider.overrideWith(_FakeConnection.new),
      ],
    );
    pending = null;
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    importSongBundleFromBytes(context, ref, pending!),
                child: const Text('import-now'),
              ),
            ),
          ),
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
  });

  tearDown(() async {
    harness.dispose();
    await testDb.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> runImport(WidgetTester tester, Uint8List bytes) async {
    pending = bytes;
    await tester.tap(find.text('import-now'));
    await tester.pumpAndSettle();
  }

  Future<void> wipe() async {
    await db.songs.deleteAll();
    await db.assets.deleteAll();
    await db.songLinks.deleteAll();
  }

  Future<int> songCount() async => (await db.songs.select().get()).length;

  String lastSnackBar() =>
      ((harness.messenger.shownSnackBars.last.content) as Text).data!;

  /// A bundle holding a song that diverges from the one stored here: same
  /// uuid, different content, and not built on mine.
  Future<Song> diverged(String title) async {
    final song = await createLocalSong(
      Song.local(title: title, lyrics: 'kapott'),
    );
    final bytes = await exportSongBundle([song.uuid]);
    pending = bytes;
    await (db.songs.update()..where((s) => s.uuid.equals(song.uuid))).write(
      SongsCompanion(
        lyrics: const Value('saját'),
        checkpoints: Value(const []),
      ),
    );
    return song;
  }

  group('import', () {
    testWidgets('a new song is imported and opened', (tester) async {
      final song = await createLocalSong(
        Song.local(title: 'Új dal', lyrics: 'v1'),
      );
      final bytes = await exportSongBundle([song.uuid]);
      await wipe();

      await pumpApp(tester);
      await runImport(tester, bytes);

      expect(await dbSongFromUuid(song.uuid), isNotNull);
      expect(find.text('song-page-${song.uuid}'), findsOneWidget);
      expect(lastSnackBar(), contains('1 új dal'));
    });

    testWidgets('a conflict asks; keeping both is the default', (tester) async {
      final song = await diverged('Közös dal');
      await pumpApp(tester);
      await runImport(tester, pending!);

      expect(find.text('Közös dal'), findsOneWidget);
      expect(
        find.text(
          'Ezt a dalt te is szerkesztetted, és a kapott változat is eltér.',
        ),
        findsOneWidget,
      );
      expect(find.text('Felülírás'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Mindkettő megtartása'),
            )
            .selected,
        isTrue,
      );
      // Nothing is written until confirmed.
      expect(await songCount(), 1);

      await tester.tap(find.text('Importálás'));
      await tester.pumpAndSettle();

      expect(await songCount(), 2);
      expect((await dbSongFromUuid(song.uuid))!.lyrics, 'saját');
      expect(lastSnackBar(), contains('1 másolat készült'));
    });

    testWidgets('choosing Felülírás replaces my song', (tester) async {
      final song = await diverged('Közös dal');
      await pumpApp(tester);
      await runImport(tester, pending!);

      await tester.tap(find.text('Felülírás'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importálás'));
      await tester.pumpAndSettle();

      expect(await songCount(), 1);
      expect((await dbSongFromUuid(song.uuid))!.lyrics, 'kapott');
    });

    testWidgets('cancelling the choices writes nothing', (tester) async {
      final song = await diverged('Közös dal');
      await pumpApp(tester);
      await runImport(tester, pending!);

      await tester.tap(find.text('Mégse'));
      await tester.pumpAndSettle();

      expect(await songCount(), 1);
      expect((await dbSongFromUuid(song.uuid))!.lyrics, 'saját');
      expect(harness.messenger.shownSnackBars, isEmpty);
    });

    testWidgets('a newer bundle version asks to update the app', (
      tester,
    ) async {
      final song = await createLocalSong(Song.local(title: 'X'));
      final bytes = await exportSongBundle([song.uuid]);
      final archive = ZipDecoder().decodeBytes(bytes);
      final manifest = jsonDecode(
        utf8.decode(archive.findFile('manifest.json')!.readBytes()!),
      ) as Map;
      manifest['version'] = 99;
      final out = Archive()
        ..addFile(
          ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))),
        );
      await wipe();

      await pumpApp(tester);
      await runImport(tester, Uint8List.fromList(ZipEncoder().encode(out)));

      expect(lastSnackBar(), contains('Frissítsd az alkalmazást'));
      expect(await songCount(), 0);
    });

    testWidgets('a file that is not a bundle is refused', (tester) async {
      await pumpApp(tester);
      await runImport(tester, Uint8List.fromList(utf8.encode('hello')));

      expect(lastSnackBar(), 'Ez nem egy Sófár Hangoló dalfájl.');
      expect(await songCount(), 0);
    });

    testWidgets('an imported copy whose bank song is absent shows no '
        '"missing original" card', (tester) async {
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
      final bytes = await exportSongBundle([copy.uuid]);
      await wipe(); // the recipient has neither the copy nor the bank song

      await pumpApp(tester);
      await runImport(tester, bytes);
      expect(await dbSongFromUuid(copy.uuid), isNotNull);

      final container = harness.container;
      final status = await waitForProviderValue(
        container,
        originalSongStatusProvider((await dbSongFromUuid(copy.uuid))!),
      );
      expect(status, OriginalSongStatus.notInstalled);

      router.go('/song/local/${copy.uuid}');
      await tester.pumpAndSettle();
      expect(find.byType(LocalSongEditor), findsOneWidget);
      expect(find.text('Eredeti dal'), findsNothing);
      expect(find.textContaining('nincs meg'), findsNothing);
    });
  });

  group('share dialog', () {
    Widget appBarFor(Song song) => UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        home: Scaffold(
          appBar: SongPageAppBar(
            song: song,
            isDesktop: false,
            isMobile: false,
            constraints: const BoxConstraints(),
            summaryContent: const [],
            detailsContent: const [],
            onShowDetailsSheet: (_, _, _) {},
            detailsSheetScrollController: ScrollController(),
          ),
        ),
      ),
    );

    testWidgets('a local song is shared as a file, with no link or code', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final song = await createLocalSong(
        Song.local(title: 'Helyi dal', lyrics: 'v1'),
      );
      await tester.pumpWidget(appBarFor(song));
      await tester.tap(find.byIcon(Icons.share));
      await tester.pumpAndSettle();

      expect(find.text('Megosztás fájlként'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.byTooltip('Másolás'), findsNothing);
    });

    testWidgets('a bank song keeps the link and has no file option', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final song = Song(
        uuid: 'bank-song',
        title: 'Banki dal',
        lyrics: 'v1',
        keyField: const [],
        contentMap: const {},
        sourceBank: 'bank-x',
      );
      await tester.pumpWidget(appBarFor(song));
      await tester.tap(find.byIcon(Icons.share));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Megosztás fájlként'), findsNothing);
    });

    testWidgets(
      'a cue dialog offers the file next to the link, with a reason',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1500, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: harness.container,
            child: MaterialApp(
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showShareDialog(
                    context,
                    title: 'Lista megosztása',
                    sharedTitle: 'Lista',
                    sharedLink: Uri.parse('https://example.com/cue'),
                    fileShare: ShareFileOption(
                      fileName: 'lista.sofar',
                      note: 'A listában 1 helyi dal van.',
                      build: () async => Uint8List(0),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('A listában 1 helyi dal van.'), findsOneWidget);
        expect(find.text('Megosztás fájlként'), findsOneWidget);
      },
    );
  });
}
