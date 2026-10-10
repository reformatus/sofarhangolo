import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/ui/song/edit/autosave_indicator.dart';

Widget _wrap(AutosaveStatus status, {VoidCallback? onRetry}) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff025462)),
    ),
    home: Scaffold(
      appBar: AppBar(
        actions: [
          AutosaveIndicator(status: status, onRetry: onRetry),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('idle shows nothing', (tester) async {
    await tester.pumpWidget(_wrap(AutosaveStatus.idle));
    await tester.pumpAndSettle();

    expect(find.text('Mentés'), findsNothing);
    expect(find.text('Mentve'), findsNothing);
    expect(find.text('Mentés sikertelen'), findsNothing);
  });

  testWidgets('saving shows a spinner and label', (tester) async {
    await tester.pumpWidget(_wrap(AutosaveStatus.saving));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Mentés'), findsOneWidget);
  });

  testWidgets('saved shows check and label', (tester) async {
    await tester.pumpWidget(_wrap(AutosaveStatus.saved));

    expect(find.text('Mentve'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('upToDate keeps the check but hides the label', (tester) async {
    await tester.pumpWidget(_wrap(AutosaveStatus.upToDate));

    expect(find.text('Mentve'), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('error is visible and tappable to retry', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      _wrap(AutosaveStatus.error, onRetry: () => retried++),
    );

    expect(find.text('Mentés sikertelen'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.error_outline));
    expect(retried, 1);
  });

  testWidgets('icon slot keeps a constant size across states', (tester) async {
    var generation = 0;
    for (final status in [
      AutosaveStatus.saving,
      AutosaveStatus.saved,
      AutosaveStatus.upToDate,
      AutosaveStatus.error,
    ]) {
      await tester.pumpWidget(
        KeyedSubtree(key: ValueKey(generation++), child: _wrap(status)),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('icon-slot'))),
        const Size(20, 20),
        reason: 'status $status',
      );
    }
  });
}
