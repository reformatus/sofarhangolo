import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/ui/song/widgets/edit_song_button.dart';

Song _song({required String uuid, required String? sourceBank}) => Song(
  uuid: uuid,
  title: 'Dal $uuid',
  keyField: const [],
  contentMap: const {},
  sourceBank: sourceBank,
);

GoRouter _router(Song song) => GoRouter(
  initialLocation: '/song',
  routes: [
    GoRoute(
      path: '/song',
      builder: (context, state) => Scaffold(body: EditSongButton(song)),
    ),
    GoRoute(
      path: '/song/local/:uuid',
      builder: (context, state) =>
          Scaffold(body: Text('editor ${state.pathParameters['uuid']}')),
    ),
  ],
);

void main() {
  testWidgets('local song opens the editor directly', (tester) async {
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: _router(_song(uuid: 'local-1', sourceBank: localBankUuid)),
      ),
    );

    await tester.tap(find.text('Szerkesztés'));
    await tester.pumpAndSettle();

    expect(find.text('editor local-1'), findsOneWidget);
  });

  testWidgets('bank song confirms the copy before editing', (tester) async {
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: _router(_song(uuid: 'bank-1', sourceBank: 'bank-1')),
      ),
    );

    await tester.tap(find.text('Szerkesztés'));
    await tester.pumpAndSettle();

    // No direct navigation; the explanation dialog is shown instead.
    expect(find.text('editor bank-1'), findsNothing);
    expect(find.text('Dal szerkesztése'), findsOneWidget);
    expect(find.textContaining('helyi másolat'), findsOneWidget);
    expect(find.text('Másolat szerkesztése'), findsOneWidget);
  });
}
