import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:sofarhangolo/data/log/provider.dart';
import 'package:sofarhangolo/services/ui/messenger_service.dart';

class _UiTestHarness {
  _UiTestHarness({required this.container, required this.messenger});

  final ProviderContainer container;
  final MessengerService messenger;
}

Future<_UiTestHarness> _pumpApp(WidgetTester tester) async {
  final messenger = MessengerService();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        messengerServiceProviderProvider.overrideWithValue(messenger),
      ],
      child: MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(accessibleNavigation: false),
            child: child!,
          );
        },
        scaffoldMessengerKey: messenger.scaffoldMessengerKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );

  final context = tester.element(find.byType(Scaffold));
  return _UiTestHarness(
    container: ProviderScope.containerOf(context),
    messenger: messenger,
  );
}

void _addWarningLog(ProviderContainer container, String message) {
  container
      .read(logMessagesProvider.notifier)
      .addRecord(LogRecord(Level.WARNING, message, 'test'));
}

void main() {
  testWidgets(
    'new warning snackbar replaces previous one immediately (no queue)',
    (tester) async {
      final harness = await _pumpApp(tester);

      _addWarningLog(harness.container, 'first warning');
      await tester.pump();
      expect(find.text('first warning'), findsOneWidget);

      _addWarningLog(harness.container, 'second warning');
      await tester.pump();

      expect(find.text('second warning'), findsOneWidget);
      expect(find.text('first warning'), findsNothing);

      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
    },
  );

  testWidgets('warning snackbar auto-dismisses after 6 seconds', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);

    _addWarningLog(harness.container, 'auto dismiss warning');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('auto dismiss warning'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('auto dismiss warning'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('auto dismiss warning'), findsNothing);
  });

  testWidgets('warning snackbar has right-side close button that dismisses it', (
    tester,
  ) async {
    final harness = await _pumpApp(tester);

    _addWarningLog(harness.container, 'close me warning');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final closeButton = find.byIcon(Icons.close);
    final message = find.text('close me warning');

    expect(closeButton, findsOneWidget);
    expect(message, findsOneWidget);

    final closeButtonDx = tester.getTopLeft(closeButton).dx;
    final messageDx = tester.getTopLeft(message).dx;
    expect(closeButtonDx, greaterThan(messageDx));

    await tester.tap(closeButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('close me warning'), findsNothing);

    await tester.pump(const Duration(seconds: 7));
    await tester.pump();
  });
}
