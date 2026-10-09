import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:sofarhangolo/data/log/provider.dart';
import 'package:sofarhangolo/services/error/app_error.dart';
import 'package:sofarhangolo/ui/common/log/dialog.dart';

Future<void> _pump(WidgetTester tester, LogRecord record) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LogMessageCard(message: LogMessage(record)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the log message is the single card title, errors add actions', (
    tester,
  ) async {
    await _pump(
      tester,
      LogRecord(
        Level.SEVERE,
        'Hiba a tárak frissítésének indításakor',
        'test',
        AppError.from(
          FormatException('bad json'),
          stackTrace: StackTrace.current,
        ),
        StackTrace.current,
      ),
    );

    // One title only: the log message, not the error category label.
    expect(find.text('Hiba a tárak frissítésének indításakor'), findsOneWidget);
    expect(find.text('Alkalmazáshiba'), findsNothing);
    expect(find.textContaining('FormatException: bad json'), findsOneWidget);
    expect(find.text('Részletek másolása'), findsOneWidget);
    expect(find.text('Hibajelentés'), findsOneWidget);
    // Unread marker sits in front of the timestamp; no per-entry check
    // button.
    expect(find.byKey(const ValueKey('log-unread-dot')), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('read messages show no unread dot', (tester) async {
    final record = LogRecord(Level.INFO, 'Minden rendben', 'test');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LogMessageCard(message: LogMessage.read(record)),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('log-unread-dot')), findsNothing);
  });

  testWidgets('the time sits above the card and includes seconds', (
    tester,
  ) async {
    await _pump(tester, LogRecord(Level.INFO, 'Minden rendben', 'test'));

    expect(find.textContaining(RegExp(r'^\d{2}:\d{2}:\d{2}$')), findsOneWidget);
  });

  testWidgets('classified errors keep the friendly body, hide the detail', (
    tester,
  ) async {
    await _pump(
      tester,
      LogRecord(
        Level.WARNING,
        'Hiba a tárak frissítése közben',
        'test',
        AppError.from(SocketException('down')),
      ),
    );

    expect(find.text('Hiba a tárak frissítése közben'), findsOneWidget);
    expect(find.textContaining('Nincs stabil kapcsolat'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
    // Network errors are warnings: no report button.
    expect(find.text('Hibajelentés'), findsNothing);
  });

  testWidgets('messages without an error still get a card', (tester) async {
    await _pump(tester, LogRecord(Level.INFO, 'Minden rendben', 'test'));

    expect(find.text('Minden rendben'), findsOneWidget);
  });

  testWidgets('plain errors still get a proper card', (tester) async {
    await _pump(
      tester,
      LogRecord(Level.SEVERE, 'Váratlan hiba', 'test', StateError('boom')),
    );

    expect(find.text('Váratlan hiba'), findsOneWidget);
    expect(find.textContaining('Bad state: boom'), findsOneWidget);
  });
}
