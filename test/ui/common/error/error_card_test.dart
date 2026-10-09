import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/services/error/app_error.dart';
import 'package:sofarhangolo/ui/common/error/card.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets('unexpected app errors show the failure without boilerplate', (
    tester,
  ) async {
    await _pump(
      tester,
      LErrorCard.fromError(
        error: const FormatException('bad json'),
        stackTrace: StackTrace.current,
      ),
    );

    // The title carries the friendly framing; the failure text goes to
    // its own code box, and the generic boilerplate body is gone.
    expect(find.textContaining('Váratlan feldolgozási hiba'), findsNothing);
    expect(find.textContaining('FormatException: bad json'), findsOneWidget);
  });

  testWidgets('classified errors keep a friendly body and no failure box', (
    tester,
  ) async {
    await _pump(
      tester,
      LErrorCard.fromError(error: SocketException('Network is unreachable')),
    );

    expect(find.textContaining('Nincs stabil kapcsolat'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
  });

  testWidgets('errors with both keep the friendly body and the failure box', (
    tester,
  ) async {
    await _pump(
      tester,
      LErrorCard.fromError(
        error: DioException(
          requestOptions: RequestOptions(path: '/songs'),
          type: DioExceptionType.transformTimeout,
          message: 'transform took too long',
        ),
        stackTrace: StackTrace.current,
      ),
    );

    expect(find.textContaining('túl sokáig tartott'), findsOneWidget);
    expect(find.textContaining('transform took too long'), findsOneWidget);
  });

  testWidgets('a body override keeps the failure box', (tester) async {
    await _pump(
      tester,
      LErrorCard.fromAppError(
        error: AppError.from(const FormatException('bad json')),
        message: 'Egyedi üzenet',
      ),
    );

    expect(find.text('Egyedi üzenet'), findsOneWidget);
    expect(find.textContaining('FormatException: bad json'), findsOneWidget);
  });

  testWidgets('copy and report share a row above the mobile breakpoint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      LErrorCard.fromError(
        error: const FormatException('bad json'),
        stackTrace: StackTrace.current,
      ),
    );

    expect(
      tester.getCenter(find.text('Részletek másolása')).dy,
      tester.getCenter(find.text('Hibajelentés')).dy,
    );
  });

  testWidgets('copy and report stack below the mobile breakpoint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      LErrorCard.fromError(
        error: const FormatException('bad json'),
        stackTrace: StackTrace.current,
      ),
    );

    expect(
      tester.getCenter(find.text('Részletek másolása')).dy,
      isNot(tester.getCenter(find.text('Hibajelentés')).dy),
    );
  });

  testWidgets('retry owns the primary slot, copy stays tertiary', (
    tester,
  ) async {
    await _pump(
      tester,
      LErrorCard.fromError(
        error: const FormatException('bad json'),
        stackTrace: StackTrace.current,
        onRetry: () {},
      ),
    );

    // Retry and the report action stay in the filled family; copy is the
    // only plain-text action.
    expect(find.widgetWithText(FilledButton, 'Újra'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Hibajelentés'), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, 'Részletek másolása'),
      findsOneWidget,
    );
  });
}
