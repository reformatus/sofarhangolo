import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/extensions.dart';
import 'package:sofarhangolo/data/song/song.dart';

Song songWith(Map<String, Object> contentMap) {
  return Song(
    uuid: 'song-1',
    title: 'Song 1',
    keyField: [],
    contentMap: contentMap,
  );
}

void main() {
  group('SongContentAccessors', () {
    group('contentString', () {
      test('returns non-blank scalar values', () {
        expect(songWith({'pdf': '/x.pdf'}).contentString('pdf'), '/x.pdf');
      });

      test('null for blank, missing, and multi-value fields', () {
        expect(songWith({'pdf': '  '}).contentString('pdf'), isNull);
        expect(songWith({}).contentString('pdf'), isNull);
        expect(
          songWith({
            'genre': ['Rock'],
          }).contentString('genre'),
          isNull,
        );
      });
    });

    group('contentList', () {
      test('passes stored lists through', () {
        expect(
          songWith({
            'genre': ['Rock', 'Pop'],
          }).contentList('genre'),
          ['Rock', 'Pop'],
        );
      });

      test('wraps a scalar as a single element', () {
        expect(songWith({'language': 'magyar'}).contentList('language'), [
          'magyar',
        ]);
      });

      test('empty for missing or blank values', () {
        expect(songWith({}).contentList('genre'), isEmpty);
        expect(songWith({'genre': ''}).contentList('genre'), isEmpty);
        expect(songWith({'genre': []}).contentList('genre'), isEmpty);
      });

      test('never splits comma-joined scalars', () {
        // Old-shape rows may hold comma-joined strings; canonical data
        // stores lists. Accessors must not resurrect comma splitting.
        expect(songWith({'genre': 'Rock, Pop'}).contentList('genre'), [
          'Rock, Pop',
        ]);
      });
    });

    group('hasContent', () {
      test('true only for non-blank content', () {
        expect(songWith({'a': 'x'}).hasContent('a'), isTrue);
        expect(songWith({'a': ' '}).hasContent('a'), isFalse);
        expect(
          songWith({
            'a': [' ', ''],
          }).hasContent('a'),
          isFalse,
        );
        expect(
          songWith({
            'a': ['', 'x'],
          }).hasContent('a'),
          isTrue,
        );
        expect(songWith({}).hasContent('a'), isFalse);
      });
    });

    group('contentDisplay', () {
      test('renders scalars as-is and lists comma-joined', () {
        expect(songWith({'a': 'x'}).contentDisplay('a'), 'x');
        expect(
          songWith({
            'a': ['Rock', 'Pop'],
          }).contentDisplay('a'),
          'Rock, Pop',
        );
        expect(
          songWith({
            'a': [' ', 'Rock', ''],
          }).contentDisplay('a'),
          'Rock',
        );
      });

      test('null for missing or blank content', () {
        expect(songWith({}).contentDisplay('a'), isNull);
        expect(songWith({'a': ''}).contentDisplay('a'), isNull);
        expect(songWith({'a': []}).contentDisplay('a'), isNull);
      });
    });

    group('sheet asset accessors', () {
      test('pdfRef and svgRef read the core file fields', () {
        final song = songWith({'pdf': '/x.pdf', 'svg': ' '});

        expect(song.pdfRef, '/x.pdf');
        expect(song.svgRef, isNull);
      });

      test('hasPdf and hasSvg follow them', () {
        final song = songWith({'pdf': '/x.pdf'});

        expect(song.hasPdf, isTrue);
        expect(song.hasSvg, isFalse);
      });
    });
  });
}
