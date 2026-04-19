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
/// final verses = parser.parse(song.lyrics, presentationOrder: songPresentation);
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
  List<ParsedVerse> parse(String lyrics, {String? presentationOrder}) {
    final verses = parseVerses(lyrics);
    return _applyPresentationOrder(
      verses,
      presentationOrder ?? getEmbeddedPresentationOrder(lyrics),
    );
  }

  /// Parse the raw lyrics string into structured verse data before ordering.
  List<ParsedVerse> parseVerses(String lyrics);

  /// Extract an order/flow string from the lyrics source when the format supports it.
  String? getEmbeddedPresentationOrder(String lyrics) => null;

  /// Check if the lyrics content contains chord annotations.
  bool hasChords(String lyrics, {String? presentationOrder}) {
    try {
      return parse(lyrics, presentationOrder: presentationOrder).any(
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
  String getFirstLine(String lyrics, {String? presentationOrder}) {
    try {
      final verses = parse(lyrics, presentationOrder: presentationOrder);
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
  String getText(String lyrics, {String? presentationOrder}) {
    try {
      final verseTexts = parse(lyrics, presentationOrder: presentationOrder)
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
  List<ParsedVerse> parseVerses(String lyrics) {
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
  List<ParsedVerse> parseVerses(String lyrics) {
    final cpVerses = cp.getVersesFromString(lyrics);
    return cpVerses.map(_mapChordProVerse).toList(growable: false);
  }

  @override
  String? getEmbeddedPresentationOrder(String lyrics) {
    final match = RegExp(
      r'^\s*\{flow(?:\s*:|\s+)([^}]+)\}\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(lyrics);

    return match?.group(1)?.trim();
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

List<ParsedVerse> _applyPresentationOrder(
  List<ParsedVerse> verses,
  String? presentationOrder,
) {
  final tokens = _parsePresentationOrderTokens(presentationOrder);
  if (tokens.isEmpty) {
    return verses;
  }

  final orderedVerses = tokens
      .map((token) => _matchVerseForToken(verses, token))
      .whereType<ParsedVerse>()
      .toList(growable: false);

  return orderedVerses.isEmpty ? verses : orderedVerses;
}

List<String> _parsePresentationOrderTokens(String? presentationOrder) {
  final order = presentationOrder?.trim();
  if (order == null || order.isEmpty) {
    return const [];
  }

  final hasExplicitSeparators = RegExp(r'[,;\n\r]').hasMatch(order);
  final rawTokens = hasExplicitSeparators
      ? order.split(RegExp(r'[,;\n\r]+'))
      : order.split(RegExp(r'\s+'));

  return rawTokens
      .map(_canonicalizePresentationToken)
      .whereType<String>()
      .toList(growable: false);
}

ParsedVerse? _matchVerseForToken(List<ParsedVerse> verses, String token) {
  for (final verse in verses) {
    final identifiers = {
      _normalizePresentationToken(verse.tag),
      _normalizePresentationToken(verse.type),
      if (verse.index != null)
        _normalizePresentationToken('${verse.type}${verse.index}'),
      if (verse.label case final label?) _normalizePresentationToken(label),
      if (verse.label == null || verse.label!.trim().isEmpty)
        _normalizePresentationToken(
          _defaultLabelForType(verse.type, verse.index),
        ),
    }.whereType<String>();

    if (identifiers.contains(token)) {
      return verse;
    }
  }

  return null;
}

String? _canonicalizePresentationToken(String token) {
  final normalized = _normalizePresentationToken(token);
  if (normalized == null) {
    return null;
  }

  final match = RegExp(
    r'^(VERSE|CHORUS|REFRAIN|BRIDGE|PRECHORUS|PRECHOR|TAG|CODA)([0-9]+)?$',
  ).firstMatch(normalized);
  if (match == null) {
    return normalized;
  }

  final type = switch (match.group(1)!) {
    'VERSE' => 'V',
    'CHORUS' || 'REFRAIN' => 'C',
    'BRIDGE' => 'B',
    'PRECHORUS' || 'PRECHOR' => 'P',
    'TAG' || 'CODA' => 'T',
    _ => match.group(1)!,
  };

  return '$type${match.group(2) ?? ''}';
}

String? _normalizePresentationToken(String? token) {
  if (token == null) {
    return null;
  }

  final normalized = token.trim().toUpperCase().replaceAll(
    RegExp(r'[^A-Z0-9]+'),
    '',
  );

  return normalized.isEmpty ? null : normalized;
}

String _defaultLabelForType(String type, int? index) => [
  switch (type.toUpperCase()) {
    'V' => 'Verse',
    'C' || 'R' => 'Chorus',
    'P' => 'Pre Chorus',
    'B' => 'Bridge',
    'T' => 'Tag',
    _ => type,
  },
  if (index != null) '$index',
].join(' ').trim();

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
