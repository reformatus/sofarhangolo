import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/write_song.dart';
import 'package:sofarhangolo/ui/song/widgets/edit_song_button.dart';

import '../../harness/test_database.dart';

Song _song({required String uuid, required String? sourceBank}) => Song(
  uuid: uuid,
  title: 'Dal $uuid',
  keyField: const [],
  contentMap: const {},
  sourceBank: sourceBank,
);

GoRouter _router(Song song) => GoRouter(
  initialLocation: '/origin',
  routes: [
    GoRoute(
      path: '/origin',
      builder: (context, state) => Scaffold(body: EditSongButton(song)),
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

void main() {
  late LyricDatabase testDb;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
  });

  tearDown(() async {
    await testDb.close();
  });

  Future<void> insertBankSong() async {
    await db
        .into(db.banks)
        .insert(
          BanksCompanion.insert(
            uuid: 'bank-1',
            name: 'Test Bank',
            baseUrl: Value(Uri.parse('https://example.com/')),
            parallelUpdateJobs: 1,
            amountOfSongsInRequest: 1,
            noCms: false,
            songFields: {},
            isEnabled: true,
            isOfflineMode: false,
          ),
        );
    await db.into(db.songs).insert(
      _song(uuid: 'bank-1', sourceBank: 'bank-1'),
      mode: InsertMode.insertOrReplace,
    );
  }

  testWidgets('local song uses a tonal button and opens the editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: _router(
          _song(uuid: 'local-1', sourceBank: localBankUuid),
        ),
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Szerkesztés'), findsOneWidget);

    await tester.tap(find.text('Szerkesztés'));
    await tester.pumpAndSettle();

    expect(find.text('editor:local-1'), findsOneWidget);
  });

  testWidgets('bank song offers "Másolat szerkesztése" and explains the copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: _router(_song(uuid: 'bank-1', sourceBank: 'bank-1')),
      ),
    );

    // The text button carries the copy wording.
    expect(
      find.widgetWithText(TextButton, 'Másolat szerkesztése'),
      findsOneWidget,
    );

    await tester.tap(find.text('Másolat szerkesztése'));
    await tester.pumpAndSettle();

    // No direct navigation; the explanation dialog is shown instead.
    expect(find.text('editor:bank-1'), findsNothing);
    expect(find.text('Dal szerkesztése'), findsOneWidget);
    expect(find.textContaining('helyi másolat'), findsOneWidget);
  });

  testWidgets('bank song: back from the editor lands on the new copy', (
    tester,
  ) async {
    await insertBankSong();
    final router = _router(_song(uuid: 'bank-1', sourceBank: 'bank-1'));
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('Másolat szerkesztése'));
    await tester.pumpAndSettle();

    // Confirm in the dialog (the origin button is a TextButton).
    await tester.tap(
      find.widgetWithText(FilledButton, 'Másolat szerkesztése'),
    );
    await tester.pumpAndSettle();

    final editorText = tester
        .widget<Text>(find.textContaining('editor:'))
        .data!;
    final copiedUuid = editorText.substring('editor:'.length);
    expect(copiedUuid, isNotEmpty);

    // Back from the editor shows the copy's own page, not the original.
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('songpage:$copiedUuid'), findsOneWidget);
  });

  testWidgets('bank song with an existing copy offers to edit it', (
    tester,
  ) async {
    await insertBankSong();
    final copy = await copySongToLocal(
      _song(uuid: 'bank-1', sourceBank: 'bank-1'),
    );

    final router = _router(_song(uuid: 'bank-1', sourceBank: 'bank-1'));
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('Másolat szerkesztése'));
    await tester.pumpAndSettle();

    // The dialog mentions the copy and offers the primary "edit existing".
    expect(find.textContaining('már készült helyi másolat'), findsOneWidget);
    expect(find.text('Meglévő másolat szerkesztése'), findsOneWidget);

    await tester.tap(find.text('Meglévő másolat szerkesztése'));
    await tester.pumpAndSettle();

    expect(find.text('editor:${copy.uuid}'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('songpage:${copy.uuid}'), findsOneWidget);
  });
}
