import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/ui/common/notice/card.dart';
import 'package:sofarhangolo/ui/song/edit/lyrics_editor.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Color(0xff025462)),
    ),
    home: Scaffold(body: child),
  );
}

/// Sends an incremental editing-value update, exactly what the engine does for
/// a single keystroke (as opposed to [WidgetTester.enterText], which replaces
/// the whole text at once).
void _type(WidgetTester tester, String text, int caret) {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    ),
  );
}

/// Unmounts the editor (letting its dispose-time flush run with a live
/// controller) and only then releases the controller.
Future<void> _tearDownEditor(
  WidgetTester tester,
  TextEditingController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

void main() {
  testWidgets('fills all available space', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _wrap(OpenSongLyricsEditor(controller: controller)),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(OpenSongLyricsEditor)),
      const Size(800, 600),
    );

    await _tearDownEditor(tester, controller);
  });

  testWidgets('long lines scroll horizontally instead of wrapping', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _wrap(OpenSongLyricsEditor(controller: controller)),
    );

    await tester.enterText(find.byType(EditableText), 'x' * 500);
    await tester.pump();
    expect(tester.takeException(), isNull);

    final horizontalScrollables = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
    );
    final state = tester.state<ScrollableState>(horizontalScrollables.first);
    // 500 monospace characters are far wider than the 800px test viewport.
    expect(state.position.maxScrollExtent, greaterThan(0));

    await _tearDownEditor(tester, controller);
  });

  testWidgets('auto-inserts a leading space on a new line', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _wrap(OpenSongLyricsEditor(controller: controller)),
    );

    await tester.enterText(find.byType(EditableText), '[V1]');
    await tester.pump();

    // Pressing Enter: the caret lands on the new, empty line.
    _type(tester, '[V1]\n', 5);
    await tester.pump();

    expect(controller.text, '[V1]\n ');
    expect(controller.selection.baseOffset, 6);

    await _tearDownEditor(tester, controller);
  });

  testWidgets('a row marker replaces the auto-inserted space', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _wrap(OpenSongLyricsEditor(controller: controller)),
    );

    await tester.enterText(find.byType(EditableText), '[V1]\n');
    await tester.pump();
    expect(controller.text, '[V1]\n ');

    // Typing `.` right after the auto space makes it a chord line.
    _type(tester, '[V1]\n .', 7);
    await tester.pump();

    expect(controller.text, '[V1]\n.');
    expect(controller.selection.baseOffset, 6);

    await _tearDownEditor(tester, controller);
  });

  testWidgets('a lyric line that starts with a dot is still reachable', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _wrap(OpenSongLyricsEditor(controller: controller)),
    );

    await tester.enterText(find.byType(EditableText), '[V1]\n');
    await tester.pump();
    expect(controller.text, '[V1]\n ');

    // Typing a space first keeps the single leading space (no doubling)...
    _type(tester, '[V1]\n  ', 7);
    await tester.pump();
    expect(controller.text, '[V1]\n ');

    // ...so the dot that follows is appended normally: " .".
    _type(tester, '[V1]\n .', 7);
    await tester.pump();
    expect(controller.text, '[V1]\n .');

    await _tearDownEditor(tester, controller);
  });

  testWidgets('focus loss adds the missing leading spaces', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _wrap(OpenSongLyricsEditor(controller: controller)),
    );

    await tester.enterText(find.byType(EditableText), '[V1]\nHello\n.C G');
    await tester.pump();
    expect(controller.text, '[V1]\nHello\n.C G');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(controller.text, '[V1]\n Hello\n.C G');

    await _tearDownEditor(tester, controller);
  });

  testWidgets('the format warning appears and disappears', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _wrap(OpenSongLyricsEditor(controller: controller)),
    );

    await tester.enterText(find.byType(EditableText), '.C G\nHello');
    await tester.pump();
    expect(find.byType(LNoticeCard), findsOneWidget);
    expect(find.text('Hibás OpenSong formátum'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '.C G\n Hello');
    await tester.pump();
    expect(find.byType(LNoticeCard), findsNothing);

    await _tearDownEditor(tester, controller);
  });

  testWidgets('correctly formatted input is left untouched', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _wrap(OpenSongLyricsEditor(controller: controller)),
    );

    await tester.enterText(find.byType(EditableText), '[V1]\n Hello\n.C G');
    await tester.pump();
    expect(controller.text, '[V1]\n Hello\n.C G');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(controller.text, '[V1]\n Hello\n.C G');

    await _tearDownEditor(tester, controller);
  });

  testWidgets('CRLF input is tolerated', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _wrap(OpenSongLyricsEditor(controller: controller)),
    );

    await tester.enterText(find.byType(EditableText), '[V1]\r\nHello\r\n.C G');
    await tester.pump();

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(controller.text, '[V1]\r\n Hello\r\n.C G');

    await _tearDownEditor(tester, controller);
  });

  testWidgets('info button opens the format help dialog', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _wrap(OpenSongLyricsEditor(controller: controller)),
    );

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(find.text('OpenSong formátum'), findsOneWidget);

    // The guide documents the operations the editor relies on.
    expect(find.textContaining('[V1]'), findsWidgets);
    expect(find.textContaining('.C'), findsWidgets);
    expect(find.textContaining('__Hello'), findsWidgets);
    expect(find.textContaining(';itt'), findsWidgets);
    expect(find.textContaining('-!!'), findsWidgets);
    expect(find.textContaining('||'), findsWidgets);
    expect(find.textContaining('CRLF'), findsWidgets);

    await _tearDownEditor(tester, controller);
  });
}
