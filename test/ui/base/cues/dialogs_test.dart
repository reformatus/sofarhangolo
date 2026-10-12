import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/services/cue/write_cue.dart';
import 'package:sofarhangolo/ui/base/cues/dialogs.dart';
import 'package:sofarhangolo/ui/cue/session/session_provider.dart';

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

  Future<void> pumpDialogHost(WidgetTester tester, Cue cue) async {
    // A router, because ConfirmDialog pops itself via `context.pop()`.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => DeleteCueDialog(cue: cue),
                ),
                child: const Text('open-dialog'),
              ),
            ),
          ),
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
  }

  Future<bool> cueRowExists(String uuid) async {
    final rows = await (db.cues.select()
          ..where((c) => c.uuid.equals(uuid)))
        .get();
    return rows.isNotEmpty;
  }

  testWidgets('deleting the active cue closes its session first', (
    tester,
  ) async {
    final cue = await insertNewCue(title: 'Aktív lista', description: '');
    await harness.container
        .read(activeCueSessionProvider.notifier)
        .load(cue.uuid);
    await waitForProviderValue(harness.container, activeCueSessionProvider);
    expect(
      harness.container.read(activeCueSessionProvider).value?.cue.uuid,
      cue.uuid,
    );

    await pumpDialogHost(tester, cue);
    await tester.tap(find.text('open-dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Törlés'));
    await tester.pumpAndSettle();

    expect(await cueRowExists(cue.uuid), isFalse);
    expect(harness.container.read(activeCueSessionProvider).value, isNull);
  });

  testWidgets('deleting an inactive cue leaves the active session alone', (
    tester,
  ) async {
    final activeCue = await insertNewCue(
      title: 'Aktív lista',
      description: '',
    );
    final otherCue = await insertNewCue(title: 'Más lista', description: '');
    await harness.container
        .read(activeCueSessionProvider.notifier)
        .load(activeCue.uuid);
    await waitForProviderValue(harness.container, activeCueSessionProvider);

    await pumpDialogHost(tester, otherCue);
    await tester.tap(find.text('open-dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Törlés'));
    await tester.pumpAndSettle();

    expect(await cueRowExists(otherCue.uuid), isFalse);
    expect(
      harness.container.read(activeCueSessionProvider).value?.cue.uuid,
      activeCue.uuid,
    );
  });
}
