import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/lyrics/format.dart';
import 'package:sofarhangolo/data/song/lyrics/parser.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/text_export/song_lyrics.dart';

void main() {
  const lyrics =
      '[V1]\n.  C        G\nSzállnak az ég felé a felhők\nMásodik sor\n\n'
      '[C]\nRefrénsor\n\n'
      '[B]\nHídsor';

  List<ParsedVerse> parseVerses() =>
      LyricsParser.forFormat(LyricsFormat.opensong).parse(lyrics);

  group('friendlyVerseText', () {
    test('prefixes the pretty verse header and drops chords', () {
      final verses = parseVerses();

      expect(
        friendlyVerseText(verses[0]),
        'Versszak 1\nSzállnak az ég felé a felhők\nMásodik sor',
      );
      expect(friendlyVerseText(verses[1]), 'Refrén\nRefrénsor');
      expect(friendlyVerseText(verses[2]), 'Bridge\nHídsor');
    });
  });

  group('friendlySongLyrics', () {
    test('separates verses with a blank line and records block offsets', () {
      final friendly = friendlySongLyrics(parseVerses());

      expect(
        friendly.text,
        'Versszak 1\nSzállnak az ég felé a felhők\nMásodik sor\n\n'
        'Refrén\nRefrénsor\n\n'
        'Bridge\nHídsor',
      );

      expect(friendly.blocks, hasLength(3));

      // Each block's offsets must slice exactly its own verse text.
      for (final (i, block) in friendly.blocks.indexed) {
        expect(
          friendly.text.substring(block.start, block.end),
          friendlyVerseText(parseVerses()[i]),
          reason: 'Block $i offsets must round-trip to its verse text',
        );
        expect(block.verseIndex, i);
      }
    });

    test('keeps original verse indices in blocks', () {
      final friendly = friendlySongLyrics(parseVerses());

      expect(friendly.blocks.map((b) => b.verseIndex), [0, 1, 2]);
    });
  });

  group('friendlySongLyricsOf', () {
    test('returns empty lyrics for a song without lyrics', () {
      final friendly = friendlySongLyricsOf(
        Song(
          uuid: 's',
          title: 'Üres',
          keyField: const [],
          contentMap: const {},
        ),
      );

      expect(friendly.text, isEmpty);
      expect(friendly.blocks, isEmpty);
    });
  });
}
