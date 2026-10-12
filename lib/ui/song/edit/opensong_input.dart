import 'package:flutter/widgets.dart';

/// Pure OpenSong input helpers used by [OpenSongLyricsEditor].
///
/// The editor itself is a raw [EditableText] without `inputFormatters` (lines
/// must never wrap), so these functions keep every text transformation
/// testable without a widget: they map a [TextEditingValue] (or a plain string)
/// to the value that should end up in the controller.

/// The characters that, as the first character of a row, mark a *non-lyric*
/// row in the OpenSong format as this app reads it:
///
/// * `.` — chord line
/// * `;` — comment
/// * `-` — printing instruction / unsupported line
/// * `[` — section tag
/// * `|` — presentation marker (blank line, or new slide with `||`)
///
/// Digits (`1`, `2`, …) can also open a row — a *numbered* lyric line — but
/// those are valid lyric rows, so they are handled separately.
const Set<String> openSongNonLyricMarkers = {'.', ';', '-', '[', '|'};

/// Whether [character] marks the start of a non-lyric row
/// (see [openSongNonLyricMarkers]).
bool isNonLyricRowStart(String character) =>
    openSongNonLyricMarkers.contains(character);

/// Whether [character] may replace an auto-inserted leading space: a non-lyric
/// marker or a digit (numbered lyric line).
bool isOpenSongRowMarker(String character) =>
    isNonLyricRowStart(character) || _isAsciiDigit(character);

/// A leading space that was inserted automatically at [offset], armed so the
/// next typed character can replace it (see [replaceMarkerAfterAutoSpace]).
typedef AutoLeadingSpace = ({TextEditingValue value, int offset});

/// Inserts a leading space when [next]'s collapsed caret sits at the start of a
/// new empty line, moving the caret after it.
///
/// Returns `null` when nothing has to change. Deletions are deliberately
/// ignored (`next.text` shorter than `previous.text`): backspacing the space
/// away is how the user removes an unwanted auto-space, and re-adding it here
/// would make the space impossible to delete.
AutoLeadingSpace? autoLeadingSpace(
  TextEditingValue previous,
  TextEditingValue next,
) {
  if (next.text.length < previous.text.length) return null;

  final selection = next.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;

  final caret = selection.baseOffset;
  if (caret < 0 || caret > next.text.length) return null;

  // The caret is on an empty line when it is both the start and the end of the
  // line it sits on (the next character is a newline, or the text ends here).
  if (_lineStartBefore(next.text, caret) != caret) return null;
  if (_lineEndAfter(next.text, caret) != caret) return null;

  return (
    value: TextEditingValue(
      text: '${next.text.substring(0, caret)} ${next.text.substring(caret)}',
      selection: TextSelection.collapsed(offset: caret + 1),
    ),
    offset: caret,
  );
}

/// Applies the one-time row-marker override for a space auto-inserted at
/// [spaceOffset].
///
/// When the very next character typed is a row marker ([isOpenSongRowMarker])
/// it replaces the auto-inserted space instead of being appended after it, so
/// `.C` becomes a chord line and `[V1]` a section tag. The override fires *at
/// most once* per auto-inserted space, which is what keeps a lyric line that
/// starts with a dot reachable: typing a plain space keeps exactly one leading
/// space, and the following `.` is then appended normally, giving ` .`.
///
/// Returns the corrected value, or `null` when [next] is not a single
/// character inserted right after the auto space.
TextEditingValue? replaceMarkerAfterAutoSpace(
  TextEditingValue previous,
  TextEditingValue next,
  int spaceOffset,
) {
  if (spaceOffset < 0 || spaceOffset >= previous.text.length) return null;
  if (previous.text[spaceOffset] != ' ') return null;
  if (next.text.length != previous.text.length + 1) return null;

  final selection = next.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  if (selection.baseOffset != spaceOffset + 2) return null;

  final typed = next.text[spaceOffset + 1];
  final expected =
      previous.text.substring(0, spaceOffset + 1) +
      typed +
      previous.text.substring(spaceOffset + 1);
  if (next.text != expected) return null;

  // A typed space collapses back to the single leading space, so the next
  // character (e.g. `.`) is appended after a real lyric leading space.
  if (typed == ' ') {
    return TextEditingValue(
      text: previous.text,
      selection: TextSelection.collapsed(offset: spaceOffset + 1),
    );
  }

  if (!isOpenSongRowMarker(typed)) return null;

  // Swap the auto-inserted space for the marker, keeping the caret after it.
  return TextEditingValue(
    text:
        '${previous.text.substring(0, spaceOffset)}$typed'
        '${previous.text.substring(spaceOffset + 1)}',
    selection: TextSelection.collapsed(offset: spaceOffset + 1),
  );
}

/// Adds the mandatory leading space to lyric lines that lack one.
///
/// Blank lines and non-lyric rows — chord, comment, instruction, section-tag
/// and presentation-marker lines, plus numbered lyric lines — are left
/// untouched, as are lines that already start with a space. CRLF line endings
/// are preserved because only `\n` is used as the separator.
String ensureLyricLeadingSpaces(String text) {
  if (text.isEmpty) return text;
  return text.split('\n').map(_withLeadingSpaceIfLyric).join('\n');
}

/// Whether [text] is invalid OpenSong: it contains at least one chord line but
/// also at least one lyric line that does not start with a space.
bool hasOpenSongFormattingWarning(String text) {
  var hasChordLine = false;
  var hasUnspacedLyric = false;

  for (final line in text.split('\n')) {
    final body = _withoutCarriageReturn(line);
    if (body.isEmpty) continue;

    if (body.startsWith('.')) {
      // A whitespace-only chord line (`.` plus spaces) is ignored by the
      // parser, so it does not make the format invalid.
      if (body.trim().length > 1) hasChordLine = true;
    } else if (!body.startsWith(' ') &&
        !isNonLyricRowStart(body[0]) &&
        !_isAsciiDigit(body[0])) {
      hasUnspacedLyric = true;
    }

    if (hasChordLine && hasUnspacedLyric) return true;
  }

  return false;
}

String _withLeadingSpaceIfLyric(String line) {
  final body = _withoutCarriageReturn(line);
  if (body.isEmpty || body.startsWith(' ')) return line;
  if (isNonLyricRowStart(body[0]) || _isAsciiDigit(body[0])) return line;
  return ' $line';
}

String _withoutCarriageReturn(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

bool _isAsciiDigit(String character) {
  if (character.length != 1) return false;
  final code = character.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

int _lineStartBefore(String text, int offset) {
  if (offset <= 0) return 0;
  final index = text.lastIndexOf('\n', offset - 1);
  return index == -1 ? 0 : index + 1;
}

int _lineEndAfter(String text, int offset) {
  final index = text.indexOf('\n', offset);
  return index == -1 ? text.length : index;
}
