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
  });
}
