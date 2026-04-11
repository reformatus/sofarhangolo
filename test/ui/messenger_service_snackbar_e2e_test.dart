import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/services/ui/messenger_service.dart';

Future<MessengerService> _pumpApp(WidgetTester tester) async {
  final messenger = MessengerService();

  await tester.pumpWidget(
    MaterialApp(
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
  );

  return messenger;
}

void main() {
  testWidgets('showSnackBarReplacingCurrent replaces active snackbar', (
    tester,
  ) async {
    final messenger = await _pumpApp(tester);

    messenger.showSnackBarReplacingCurrent(
      const SnackBar(
        content: Text('first snackbar'),
        duration: Duration(seconds: 10),
      ),
    );
    await tester.pump();
    expect(find.text('first snackbar'), findsOneWidget);

    messenger.showSnackBarReplacingCurrent(
      const SnackBar(
        content: Text('second snackbar'),
        duration: Duration(seconds: 10),
      ),
    );
    await tester.pump();

    expect(find.text('second snackbar'), findsOneWidget);
    expect(find.text('first snackbar'), findsNothing);
  });

  testWidgets('showSnackBarReplacingCurrent can force auto-hide', (tester) async {
    final messenger = await _pumpApp(tester);

    messenger.showSnackBarReplacingCurrent(
      const SnackBar(
        content: Text('force hide snackbar'),
        duration: Duration(minutes: 1),
      ),
      forceHideAfter: const Duration(seconds: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('force hide snackbar'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('force hide snackbar'), findsNothing);
  });
}
