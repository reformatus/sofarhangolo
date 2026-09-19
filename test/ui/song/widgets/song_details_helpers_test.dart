import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/ui/song/widgets/song_details_helpers.dart';

void main() {
  // Mirrors what getDetailsContent produces: each item's subtitle carries
  // break markers at its boundaries (see selectionBreakMarker).
  Widget detailItem(String title, String value) => ListTile(
    title: Text(title),
    subtitle: Text('$selectionBreakMarker$value$selectionBreakMarker'),
  );

  // The select-all/copy shortcuts used below are desktop bindings.
  testWidgets('selectable details list keeps line breaks in copied text', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      // In-memory clipboard: without a handler for the platform channel,
      // Clipboard.getData would never resolve and the test would hang.
      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            switch (call.method) {
              case 'Clipboard.setData':
                clipboardText =
                    (call.arguments as Map<String, Object?>)['text'] as String?;
                return null;
              case 'Clipboard.getData':
                return {'text': clipboardText};
              default:
                return null;
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectableDetailsList(
              children: [
                detailItem('Címzett', 'Valaki'),
                detailItem('Forrás', 'Valahol'),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Címzett'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // Bounded pumps: pumpAndSettle never settles here because the selection
      // overlay keeps scheduling frames while the selection is active.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final clipboard = await Clipboard.getData('text/plain');
      final copied = clipboard?.text;

      expect(copied, isNotNull);
      expect(
        copied,
        contains('Valaki\nForrás'),
        reason: 'codeUnits=${copied?.codeUnits}',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('drag selection across items also keeps line breaks', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            switch (call.method) {
              case 'Clipboard.setData':
                clipboardText =
                    (call.arguments as Map<String, Object?>)['text'] as String?;
                return null;
              case 'Clipboard.getData':
                return {'text': clipboardText};
              default:
                return null;
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectableDetailsList(
              children: [
                detailItem('Címzett', 'Valaki'),
                detailItem('Forrás', 'Valahol'),
              ],
            ),
          ),
        ),
      );

      // Drag-select from the middle of item 1 to the middle of item 2 —
      // the way a desktop user actually selects. Must be a mouse pointer:
      // touch drags don't select text.
      final start = tester.getCenter(find.textContaining('Valaki'));
      final end = tester.getCenter(find.textContaining('Valahol'));
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      const steps = 10;
      for (var i = 1; i <= steps; i++) {
        await gesture.moveBy(
          (end - start) * (i / steps),
          timeStamp: Duration(milliseconds: 50 * i),
        );
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final clipboard = await Clipboard.getData('text/plain');
      final copied = clipboard?.text;

      expect(copied, isNotNull);
      // Whatever part got selected, the break markers must have been
      // converted to line breaks — no raw markers may leak into the copy.
      expect(copied, isNot(contains(selectionBreakMarker)));
      expect(copied, contains('Forrás\nValahol'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
