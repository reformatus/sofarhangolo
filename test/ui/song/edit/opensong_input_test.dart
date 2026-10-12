import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/ui/song/edit/opensong_input.dart';

TextEditingValue _value(String text, [int? caret]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);

void main() {
  group('row markers', () {
    test('the non-lyric markers are recognised', () {
      for (final marker in ['.', ';', '-', '[', '|']) {
        expect(isNonLyricRowStart(marker), isTrue);
        expect(isOpenSongRowMarker(marker), isTrue);
      }
    });

    test('digits are markers for the override but are lyric rows', () {
      for (final digit in ['0', '1', '5', '9']) {
        expect(isOpenSongRowMarker(digit), isTrue);
        expect(isNonLyricRowStart(digit), isFalse);
      }
    });

    test('letters, spaces and multi-character strings are not markers', () {
      for (final other in ['a', ' ', 'é', '', 'ab']) {
        expect(isOpenSongRowMarker(other), isFalse);
        expect(isNonLyricRowStart(other), isFalse);
      }
    });
  });

  group('autoLeadingSpace', () {
    test('adds a space when the caret lands on an empty new line', () {
      final result = autoLeadingSpace(_value('abc'), _value('abc\n', 4));

      expect(result, isNotNull);
      expect(result!.value.text, 'abc\n ');
      expect(result.value.selection.baseOffset, 5);
      expect(result.offset, 4);
    });

    test('adds a space on a lone empty line', () {
      final result = autoLeadingSpace(_value('abc', 0), _value('\nabc', 0));

      expect(result!.value.text, ' \nabc');
      expect(result.value.selection.baseOffset, 1);
      expect(result.offset, 0);
    });

    test('does nothing when the line already has a leading space', () {
      expect(autoLeadingSpace(_value('abc'), _value('abc\n ', 5)), isNull);
    });

    test('does nothing when the caret is not at a line start', () {
      expect(autoLeadingSpace(_value('ab'), _value('abcd', 2)), isNull);
    });

    test('does nothing when the line is not empty', () {
      expect(autoLeadingSpace(_value('abc\n'), _value('abc\nx', 5)), isNull);
    });

    test('never re-adds a space that was just deleted', () {
      // Pressing backspace on the auto space must be able to remove it.
      expect(autoLeadingSpace(_value('abc\n ', 5), _value('abc\n', 4)), isNull);
    });

    test('does nothing for a non-collapsed selection', () {
      expect(
        autoLeadingSpace(
          _value('abc'),
          const TextEditingValue(
            text: 'abc\n',
            selection: TextSelection(baseOffset: 2, extentOffset: 4),
          ),
        ),
        isNull,
      );
    });
  });

  group('replaceMarkerAfterAutoSpace', () {
    test('a chord marker replaces the auto space', () {
      final result = replaceMarkerAfterAutoSpace(
        _value('abc\n ', 5),
        _value('abc\n .', 6),
        4,
      );

      expect(result, isNotNull);
      expect(result!.text, 'abc\n.');
      expect(result.selection.baseOffset, 5);
    });

    test('a digit replaces the auto space', () {
      final result = replaceMarkerAfterAutoSpace(
        _value('\n ', 2),
        _value('\n 1', 3),
        1,
      );

      expect(result!.text, '\n1');
      expect(result.selection.baseOffset, 2);
    });

    test('a typed space collapses to the single auto space', () {
      final result = replaceMarkerAfterAutoSpace(
        _value('\n ', 2),
        _value('\n  ', 3),
        1,
      );

      expect(result!.text, '\n ');
      expect(result.selection.baseOffset, 2);
    });

    test('a normal letter is left appended after the space', () {
      expect(
        replaceMarkerAfterAutoSpace(_value('\n ', 1), _value('\n H', 2), 0),
        isNull,
      );
    });

    test('returns null when the armed offset no longer holds a space', () {
      // After a previous replacement the offset points at the marker; a second
      // override is therefore impossible (the override fires at most once).
      expect(
        replaceMarkerAfterAutoSpace(_value('\n.', 2), _value('\n. ', 3), 1),
        isNull,
      );
    });

    test('returns null for an edit that is not a single insertion', () {
      expect(
        replaceMarkerAfterAutoSpace(_value('\n ', 2), _value('\n .x', 4), 1),
        isNull,
      );
    });
  });

  group('ensureLyricLeadingSpaces', () {
    test('adds the space only where it is missing', () {
      const input = '[V1]\nHello\n.C G\n;note\n-!!\n1Numbered\n |\n\n World';

      expect(
        ensureLyricLeadingSpaces(input),
        '[V1]\n Hello\n.C G\n;note\n-!!\n1Numbered\n |\n\n World',
      );
    });

    test('leaves correctly formatted lyrics untouched', () {
      const input = '[V1]\n Hello\n.C G';
      expect(ensureLyricLeadingSpaces(input), input);
    });

    test('preserves CRLF line endings', () {
      expect(
        ensureLyricLeadingSpaces('[V1]\r\nHello\r\n.C G'),
        '[V1]\r\n Hello\r\n.C G',
      );
    });

    test('handles empty input', () {
      expect(ensureLyricLeadingSpaces(''), '');
    });
  });

  group('hasOpenSongFormattingWarning', () {
    test('warns for a chord line next to an unspaced lyric', () {
      expect(hasOpenSongFormattingWarning('.C G\nHello'), isTrue);
    });

    test('does not warn when the lyric has its leading space', () {
      expect(hasOpenSongFormattingWarning('.C G\n Hello'), isFalse);
    });

    test('does not warn without any chord line', () {
      expect(hasOpenSongFormattingWarning('Hello\nWorld'), isFalse);
    });

    test('does not warn for valid special lines', () {
      expect(
        hasOpenSongFormattingWarning('.C G\n1Numbered\n | \n;note\n[V1]'),
        isFalse,
      );
    });

    test('ignores a whitespace-only chord line', () {
      expect(hasOpenSongFormattingWarning('.   \nHello'), isFalse);
    });

    test('tolerates CRLF', () {
      expect(hasOpenSongFormattingWarning('.C G\r\nHello'), isTrue);
      expect(hasOpenSongFormattingWarning('.C G\r\n Hello'), isFalse);
    });
  });
}
