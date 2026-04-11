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
}
