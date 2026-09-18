import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/ui/song/lyrics/text_actions/lyrics_selection_dialog.dart';

void main() {
  group('mechanics: readOnly TextField programmatic selection', () {
    testWidgets('post-frame selection is retained unfocused and after focus', (
      tester,
    ) async {
      final controller = TextEditingController(
        text: 'Verse one\nSzállnak az ég felé\nVerse two\nElmosódik',
      );
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              readOnly: true,
              controller: controller,
              focusNode: focusNode,
              maxLines: null,
            ),
          ),
        ),
      );

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 30,
      );
      await tester.pump();

      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 30),
      );
      final editableState = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      expect(
        editableState.renderEditable.selection,
        const TextSelection(baseOffset: 0, extentOffset: 30),
      );

      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 30),
        reason: 'Gaining focus must not reset a valid programmatic selection',
      );
    });
  });

  group('LyricsSelectionDialog preselection', () {
    const lyrics =
        '[V1]\n.       C        G\nSzállnak az ég felé a felhők\n\n[C]\nRefrén szöveg';

    Song song() => Song(
      uuid: 's1',
      title: 'Teszt dal',
      lyrics: lyrics,
      keyField: const [],
      contentMap: const {},
    );

    testWidgets('preselects the requested verse', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricsSelectionDialog(song: song(), initialVerseIndex: 0),
          ),
        ),
      );
      await tester.pump(); // post-frame callback applies the selection
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      final selection = field.controller!.selection;
      expect(
        selection.isCollapsed,
        isFalse,
        reason: 'Preselection was not applied; selection=$selection',
      );
      final selectedText = field.controller!.text.substring(
        selection.start,
        selection.end,
      );
      expect(selectedText, 'Versszak 1\nSzállnak az ég felé a felhők');

      // The field is focused so the selection is actually rendered.
      expect(FocusManager.instance.primaryFocus, isNotNull);
    });

    testWidgets('scrolls a far-away preselected verse into view', (
      tester,
    ) async {
      final manyVerses = List.generate(
        20,
        (i) =>
            '[V${i + 1}]\nVersszak ${i + 1} tartalma\n'
            'további sor kettő\n'
            'további sor három\n'
            'további sor négy',
      ).join('\n\n');
      final longSong = Song(
        uuid: 's2',
        title: 'Hosszú dal',
        lyrics: manyVerses,
        keyField: const [],
        contentMap: const {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LyricsSelectionDialog(song: longSong, initialVerseIndex: 19),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // The verse lives inside the TextField's rich text, so verify its
      // position via the caret rect instead of a widget lookup.
      final editableState = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final selection = editableState.widget.controller.selection;
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        scrollable.position.pixels,
        greaterThan(0),
        reason: 'The field must be scrolled towards the preselected verse',
      );

      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final caretTop = editableState.renderEditable
          .getLocalRectForCaret(TextPosition(offset: selection.start))
          .top;
      final caretGlobalTop =
          viewport.top + caretTop - scrollable.position.pixels;
      expect(caretGlobalTop, greaterThan(viewport.top));
      expect(caretGlobalTop, lessThan(viewport.bottom));
    });

    testWidgets('no preselection when initialVerseIndex is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LyricsSelectionDialog(song: song())),
        ),
      );
      await tester.pump();
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.selection.isCollapsed, isTrue);
    });
  });
}
