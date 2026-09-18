import 'package:sofarhangolo/data/song/extensions.dart';
import 'package:sofarhangolo/data/song/lyrics/parser.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/song/verse_tag_pretty.dart';

// far future todo: option to export lyrics with chords with the active transpose applied.

/// A single verse block inside [FriendlyLyrics.text].
class FriendlyLyricsBlock {
  const FriendlyLyricsBlock({
    required this.verseIndex,
    required this.start,
    required this.end,
  });

  /// Index of the verse in the parsed verse list.
  final int verseIndex;

  /// Inclusive start offset of the verse header line in [FriendlyLyrics.text].
  final int start;

  /// Exclusive end offset of the verse body in [FriendlyLyrics.text].
  final int end;
}

/// The user-friendly, exportable representation of a song's lyrics.
class FriendlyLyrics {
  const FriendlyLyrics({required this.text, required this.blocks});

  final String text;

  /// Verse blocks in document order, usable for preselection offsets.
  final List<FriendlyLyricsBlock> blocks;
}

/// User-friendly text of a single verse: pretty header line followed by the
/// lyric lines. Chords are intentionally excluded; the original OpenSong
/// source is available separately for the raw-format export.
String friendlyVerseText(ParsedVerse verse) {
  final header = getPrettyVerseTagFrom(verse.type, verse.index);
  final body = verse.lyrics.trim();
  if (header.isEmpty) return body;
  return '$header\n$body';
}

/// Builds the user-friendly lyrics of a whole song: each verse prefixed with
/// its pretty header, separated by a blank line. Chords are excluded.
FriendlyLyrics friendlySongLyrics(List<ParsedVerse> verses) {
  final buffer = StringBuffer();
  final blocks = <FriendlyLyricsBlock>[];

  for (final (index, verse) in verses.indexed) {
    final block = friendlyVerseText(verse);
    if (block.isEmpty) continue;

    if (buffer.isNotEmpty) buffer.write('\n\n');
    final start = buffer.length;
    buffer.write(block);
    blocks.add(
      FriendlyLyricsBlock(verseIndex: index, start: start, end: buffer.length),
    );
  }

  return FriendlyLyrics(text: buffer.toString(), blocks: blocks);
}

/// [friendlySongLyrics] for a [Song].
FriendlyLyrics friendlySongLyricsOf(Song song) {
  if (!song.hasLyrics) {
    return const FriendlyLyrics(text: '', blocks: []);
  }
  final verses = LyricsParser.forFormat(song.lyricsFormat).parse(song.lyrics!);
  return friendlySongLyrics(verses);
}
