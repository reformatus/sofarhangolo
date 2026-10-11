import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/ui/song/edit/lyrics_editor.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Color(0xff025462)),
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('fills all available space', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_wrap(OpenSongLyricsEditor(controller: controller)));

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(OpenSongLyricsEditor)),
      const Size(800, 600),
    );

    controller.dispose();
  });

  testWidgets('long lines scroll horizontally instead of wrapping', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_wrap(OpenSongLyricsEditor(controller: controller)));

    await tester.enterText(find.byType(EditableText), 'x' * 500);
    await tester.pump();
    expect(tester.takeException(), isNull);

    final horizontalScrollables = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
    );
    final state = tester.state<ScrollableState>(
      horizontalScrollables.first,
    );
    // 500 monospace characters are far wider than the 800px test viewport.
    expect(state.position.maxScrollExtent, greaterThan(0));

    controller.dispose();
  });

  testWidgets('info button opens the format help dialog', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_wrap(OpenSongLyricsEditor(controller: controller)));

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(find.text('OpenSong formátum'), findsOneWidget);

    controller.dispose();
  });
}
