import 'package:dart_opensong/dart_opensong.dart' as os;

import 'format.dart';

/// Abstract interface for parsing lyrics in various formats.
///
/// Each [LyricsFormat] has a corresponding parser implementation.
/// Use [LyricsParser.forFormat] to get the appropriate parser.
///
/// Example:
/// ```dart
/// final parser = LyricsParser.forFormat(song.lyricsFormat);
/// final verses = parser.parse(song.lyrics);
/// ```
sealed class LyricsParser {
  const LyricsParser();

  /// Factory to get the appropriate parser for a given format.
  factory LyricsParser.forFormat(LyricsFormat format) {
    return switch (format) {
      LyricsFormat.opensong => const OpenSongParser(),
    };
  }

  /// Parse the raw lyrics string into structured verse data.
  ///
  /// Returns a list of parsed verses that can be rendered by the UI.
  List<ParsedVerse> parse(String lyrics);

  /// Check if the lyrics content contains chord annotations.
  bool hasChords(String lyrics);

  /// Extract the first line of actual lyrics (not section headers or chords).
  ///
  /// Used for displaying a preview/subtitle of the song.
  String getFirstLine(String lyrics);

  /// Get plain text content without chords or section markers.
  ///
  /// Used for text-only display or export.
  String getText(String lyrics);
}

/// OpenSong format parser using the dart_opensong package.
///
/// OpenSong format uses:
/// - `[V]`, `[C]`, `[B]` etc. for section markers (Verse, Chorus, Bridge)
/// - Lines starting with `.` contain chords
/// - Lines starting with ` ` (space) contain lyrics
/// - `_` represents held syllables
class OpenSongParser extends LyricsParser {
  const OpenSongParser();

  @override
  List<ParsedVerse> parse(String lyrics) {
    final osVerses = os.getVersesFromString(lyrics);
    return osVerses.map((v) => OpenSongVerse(v)).toList();
  }

  @override
  bool hasChords(String lyrics) {
    // OpenSong chord lines start with a dot after newline
    return RegExp(r'\n\.').hasMatch(lyrics);
  }

  @override
  String getFirstLine(String lyrics) {
    try {
      final verses = os.getVersesFromString(lyrics);
      if (verses.isEmpty) return '';

      final firstVerse = verses.first;
      for (final part in firstVerse.parts) {
        if (part case os.VerseLine(:final segments)) {
          return segments.map((segment) => segment.lyrics).join().trim();
        }
      }

      return '';
    } catch (_) {
      return '';
    }
  }

  @override
  String getText(String lyrics) {
    return lyrics
        // Remove chord lines
        .replaceAll(RegExp(r'(\r?\n|\r)?\..*'), '')
        // Remove song part lines
        .replaceAll(RegExp(r'(.*\[|.*\|).*'), '')
        // Remove starting linebreak
        .replaceAll(RegExp(r'^(\r?\n|\r)'), '')
        // Remove multi linebreaks
        .replaceAll(RegExp(r'(\r?\n|\r){3,}'), '\n\n')
        // Remove starting space from text lines
        .replaceAll(RegExp(r'^ +', multiLine: true), '')
        // Merge multiple spaces
        .replaceAll(RegExp(r' {2,}'), ' ')
        // Remove special characters
        .replaceAll(RegExp(r'_'), '');
  }
}

/// Abstract representation of a parsed verse.
///
/// Different format parsers may return different concrete implementations,
/// but the UI should work with this common interface.
sealed class ParsedVerse {
  const ParsedVerse();

  /// The verse tag/type (e.g., "V1", "C", "B2")
  String get tag;

  /// The verse type identifier (e.g., "V" for verse, "C" for chorus)
  String get type;

  /// The verse index number (e.g., 1 for V1, 2 for V2)
  int? get index;

  /// The parsed content parts of this verse.
  /// The concrete type depends on the format parser.
  List<dynamic> get parts;
}

/// Verse implementation wrapping dart_opensong's Verse type.
class OpenSongVerse extends ParsedVerse {
  final os.Verse _verse;

  const OpenSongVerse(this._verse);

  @override
  String get tag => _verse.tag;

  @override
  String get type => _verse.type;

  @override
  int? get index => _verse.index;

  @override
  List<os.VersePart> get parts => _verse.parts;

  /// Access the underlying opensong verse for format-specific operations.
  os.Verse get raw => _verse;
}
