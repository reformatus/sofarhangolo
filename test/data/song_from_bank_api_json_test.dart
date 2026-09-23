import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/lyrics/format.dart';
import 'package:sofarhangolo/data/song/song.dart';

void main() {
  group('Song.fromBankApiJson', () {
    test('uses non-empty lyrics field when present', () {
      final song = Song.fromBankApiJson({
        'uuid': 'song-1',
        'title': 'Song 1',
        'lyrics': '[V1]\n Sor 1',
        'lyricsFormat': 'opensong',
      });

      expect(song.lyrics, equals('[V1]\n Sor 1'));
      expect(song.lyricsFormat, equals(LyricsFormat.opensong));
    });

    test('falls back to opensong when lyrics field is blank', () {
      final song = Song.fromBankApiJson({
        'uuid': 'song-2',
        'title': 'Song 2',
        'lyrics': '   ',
        'opensong': '[V1]\n Régi sor',
      });

      expect(song.lyrics, equals('[V1]\n Régi sor'));
      expect(song.lyricsFormat, equals(LyricsFormat.opensong));
    });

    test(
      'keeps escaped lyrics unchanged when caller does not normalize first',
      () {
        final song = Song.fromBankApiJson({
          'uuid': 'song-4',
          'title': 'Rock &amp; Roll',
          'lyrics': '[V1]\n Tom &amp; Jerry',
          'lyrics_format': 'opensong',
          'composer': 'A &amp; B',
        });

        expect(song.title, equals('Rock &amp; Roll'));
        expect(song.lyrics, equals('[V1]\n Tom &amp; Jerry'));
        expect(song.contentMap['composer'], equals('A &amp; B'));
      },
    );

    test('stores decoded metadata in contentMap when input is normalized', () {
      final song = Song.fromBankApiJson({
        'uuid': 'song-5',
        'title': 'Rock & Roll',
        'lyrics': '[V1]\n Tom & Jerry',
        'lyrics_format': 'opensong',
        'composer': 'A & B',
      });

      expect(song.title, equals('Rock & Roll'));
      expect(song.lyrics, equals('[V1]\n Tom & Jerry'));
      expect(song.lyricsFormat, equals(LyricsFormat.opensong));
      expect(song.contentMap['composer'], equals('A & B'));
    });

    test(
      'marks filled fields owned and blank or null-string values unowned',
      () {
        final song = Song.fromBankApiJson({
          'uuid': 'song-6',
          'title': 'Song 6',
          'lyrics': '[V1]\n Sor',
          'composer': 'Composer',
          'arranger': '',
          'translator': 'null',
        });

        expect(song.ownership!.contentKeys, equals({'composer'}));
        // Blank and literal 'null' values are still stored, just unowned.
        expect(song.contentMap['arranger'], equals(''));
        expect(song.contentMap['translator'], equals('null'));
      },
    );

    test('derives lyrics and key ownership flags from parsed values', () {
      final song = Song.fromBankApiJson({
        'uuid': 'song-7',
        'title': 'Song 7',
        'lyrics': '[V1]\n Sor',
        'key': 'C-dur, D-moll',
      });

      expect(song.ownership!.lyrics, isTrue);
      expect(song.ownership!.keyField, isTrue);
      expect(
        song.keyField,
        equals([KeyField('C', 'dur'), KeyField('D', 'moll')]),
      );
    });

    test('legacy opensong lyrics still count as owned', () {
      final song = Song.fromBankApiJson({
        'uuid': 'song-8',
        'title': 'Song 8',
        'opensong': '[V1]\n Régi sor',
      });

      expect(song.ownership!.lyrics, isTrue);
      expect(song.ownership!.keyField, isFalse);
      expect(song.lyrics, equals('[V1]\n Régi sor'));
    });

    test('blank lyrics and empty key list are marked unowned', () {
      final song = Song.fromBankApiJson({
        'uuid': 'song-9',
        'title': 'Song 9',
        'lyrics': '   ',
        'key': '  ',
      });

      expect(song.ownership!.lyrics, isFalse);
      expect(song.ownership!.keyField, isFalse);
      expect(song.lyrics, isNull);
    });
  });
}
