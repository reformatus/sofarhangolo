import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/lyrics/parser.dart';

void main() {
  group('OpenSongParser.getFirstLine', () {
    const parser = OpenSongParser();

    test('returns first lyric line from parsed verses', () {
      const lyrics = '''
[V1]
. G            D
 Áldom_ az Urat
[C]
. C
 Halleluja
''';

      expect(parser.getFirstLine(lyrics), equals('Áldom az Urat'));
    });

    test('skips non-lyric lines and empty segments', () {
      const lyrics = '''
[V1]
. C   G
. D

[V2]
 Első sor
''';

      expect(parser.getFirstLine(lyrics), isEmpty);
    });

    test('returns empty string when no lyric line is present', () {
      const lyrics = '''
[V1]
. C   G
. D
''';

      expect(parser.getFirstLine(lyrics), isEmpty);
    });
  });

  group('ChordProParser', () {
    const parser = ChordProParser();

    test('returns first lyric line from inline chord lyrics', () {
      const lyrics = '''
{title: Sample}
{start_of_verse: 1}
[C]Amazing [G]grace
{end_of_verse}
''';

      expect(parser.getFirstLine(lyrics), equals('Amazing grace'));
      expect(parser.hasChords(lyrics), isTrue);
      expect(parser.getText(lyrics), equals('Amazing grace'));
    });

    test('parses chorus recall and labels', () {
      final verses = parser.parse('''
{soc: Refrain}
[F]Halle[G]lujah
{eoc}
{chorus: Refrain}
''');

      expect(verses, hasLength(2));
      expect((verses.first.type, verses.first.label), equals(('C', 'Refrain')));
      expect((verses.last.type, verses.last.label), equals(('C', 'Refrain')));
      expect(
        (verses.last.parts.single as ParsedVerseLine).lyrics,
        equals('Hallelujah'),
      );
    });
  });
}
