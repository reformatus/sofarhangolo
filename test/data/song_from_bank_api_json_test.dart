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

    test('throws when both lyrics and opensong are missing or blank', () {
      expect(
        () => Song.fromBankApiJson({
          'uuid': 'song-3',
          'title': 'Song 3',
          'lyrics': '',
          'opensong': '   ',
        }),
        throwsException,
      );
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

    test('uses the supplied ChordPro lyrics format', () {
      final song = Song.fromBankApiJson({
        'uuid': 'song-4',
        'title': 'Song 4',
        'lyrics': '[C]Amazing grace',
        'lyricsFormat': 'chordpro',
      });

      expect(song.lyrics, equals('[C]Amazing grace'));
      expect(song.lyricsFormat, equals(LyricsFormat.chordpro));
    });

    test('exposes presentation order from song metadata', () {
      final song = Song.fromBankApiJson({
        'uuid': 'song-5',
        'title': 'Song 5',
        'lyrics': '[V1]\n First',
        'lyricsFormat': 'opensong',
        'presentation': 'C V1',
      });

      expect(song.presentationOrder, equals('C V1'));
    });
  });
}
