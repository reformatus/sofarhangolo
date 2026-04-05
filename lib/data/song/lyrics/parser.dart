import 'package:dart_chordpro/dart_chordpro.dart' as cp;
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
      LyricsFormat.chordpro => const ChordProParser(),
    };
  }

  /// Parse the raw lyrics string into structured verse data.
  ///
  /// Returns a list of parsed verses that can be rendered by the UI.
  List<ParsedVerse> parse(String lyrics);

  /// Check if the lyrics content contains chord annotations.
  bool hasChords(String lyrics) {
    try {
      return parse(lyrics).any(
        (verse) => verse.parts.whereType<ParsedVerseLine>().any(
          (line) => line.segments.any((segment) => segment.chord != null),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Extract the first line of actual lyrics (not section headers or chords).
  ///
  /// Used for displaying a preview/subtitle of the song.
  String getFirstLine(String lyrics) {
    try {
      final verses = parse(lyrics);
      if (verses.isEmpty) {
        return '';
      }

      for (final part in verses.first.parts.whereType<ParsedVerseLine>()) {
        final line = part.lyrics.trim();
        if (line.isNotEmpty) {
          return line;
        }
      }

      return '';
    } catch (_) {
      return '';
    }
  }

  /// Get plain text content without chords or section markers.
  ///
  /// Used for text-only display or export.
  String getText(String lyrics) {
    try {
      final verseTexts = parse(lyrics)
          .map(
            (verse) => verse.parts
                .map(
                  (part) => switch (part) {
                    ParsedVerseLine(:final lyrics) => lyrics.trimRight(),
                    ParsedEmptyLine() => '',
                    _ => null,
                  },
                )
                .whereType<String>()
                .join('\n')
                .trimRight(),
          )
          .where((text) => text.isNotEmpty)
          .toList();
      return verseTexts.join('\n\n');
    } catch (_) {
      return '';
    }
  }
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
    return osVerses.map(_mapOpenSongVerse).toList(growable: false);
  }
}

/// ChordPro format parser using the dart_chordpro package.
///
/// Supported ChordPro subset:
/// - inline chords like `[C]Amazing [G]grace`
/// - verse / chorus / bridge blocks
/// - chorus recall
/// - comment directives
/// - page and column breaks
class ChordProParser extends LyricsParser {
  const ChordProParser();

  @override
  List<ParsedVerse> parse(String lyrics) {
    final cpVerses = cp.getVersesFromString(lyrics);
    return cpVerses.map(_mapChordProVerse).toList(growable: false);
  }
}

class ParsedVerse {
  const ParsedVerse({
    required this.type,
    required this.index,
    required this.parts,
    this.label,
  });

  final String type;
  final int? index;
  final String? label;
  final List<ParsedVersePart> parts;

  String get tag => label ?? '$type${index ?? ''}';
}

sealed class ParsedVersePart {
  const ParsedVersePart();
}

class ParsedVerseLine extends ParsedVersePart {
  const ParsedVerseLine(this.segments);

  final List<ParsedVerseLineSegment> segments;

  String get lyrics => segments.map((segment) => segment.lyrics).join();
}

class ParsedCommentLine extends ParsedVersePart {
  const ParsedCommentLine(this.comment);

  final String comment;
}

class ParsedNewSlide extends ParsedVersePart {
  const ParsedNewSlide();
}

class ParsedEmptyLine extends ParsedVersePart {
  const ParsedEmptyLine();
}

class ParsedUnsupportedLine extends ParsedVersePart {
  const ParsedUnsupportedLine(this.original);

  final String original;
}

class ParsedVerseLineSegment {
  const ParsedVerseLineSegment(
    this.chord,
    this.lyrics, {
    this.hyphenAfter = false,
  });

  final String? chord;
  final String lyrics;
  final bool hyphenAfter;
}

ParsedVerse _mapOpenSongVerse(os.Verse verse) => ParsedVerse(
  type: verse.type,
  index: verse.index,
  parts: verse.parts.map(_mapOpenSongPart).toList(growable: false),
);

ParsedVersePart _mapOpenSongPart(os.VersePart part) => switch (part) {
  os.VerseLine(:final segments) => ParsedVerseLine(
    segments
        .map(
          (segment) => ParsedVerseLineSegment(
            segment.chord,
            segment.lyrics,
            hyphenAfter: segment.hyphenAfter,
          ),
        )
        .toList(growable: false),
  ),
  os.CommentLine(:final comment) => ParsedCommentLine(comment),
  os.NewSlide() => const ParsedNewSlide(),
  os.EmptyLine() => const ParsedEmptyLine(),
  os.UnsupportedLine(:final original) => ParsedUnsupportedLine(original),
};

ParsedVerse _mapChordProVerse(cp.Verse verse) => ParsedVerse(
  type: verse.type,
  index: verse.index,
  label: verse.label,
  parts: verse.parts.map(_mapChordProPart).toList(growable: false),
);

ParsedVersePart _mapChordProPart(cp.VersePart part) => switch (part) {
  cp.VerseLine(:final segments) => ParsedVerseLine(
    segments
        .map(
          (segment) => ParsedVerseLineSegment(
            segment.chord,
            segment.lyrics,
            hyphenAfter: segment.hyphenAfter,
          ),
        )
        .toList(growable: false),
  ),
  cp.CommentLine(:final comment) => ParsedCommentLine(comment),
  cp.NewSlide() => const ParsedNewSlide(),
  cp.EmptyLine() => const ParsedEmptyLine(),
  cp.UnsupportedLine(:final original) => ParsedUnsupportedLine(original),
};
