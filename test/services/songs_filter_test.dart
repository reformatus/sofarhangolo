import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/filter.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/field_type.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/key/state.dart';

void main() {
  group('existingFilterableFields', () {
    Song buildSong({
      required String uuid,
      required String title,
      String? key,
      Map<String, dynamic> extra = const {},
    }) {
      return Song.fromBankApiJson({
        'uuid': uuid,
        'title': title,
        'lyrics': '<song><lyrics>$title</lyrics></song>',
        'key': key,
        ...extra,
      });
    }

    test('does not add a key filter when no songs have a key', () async {
      final songs = [
        buildSong(uuid: 'song-1', title: 'Song 1'),
        buildSong(uuid: 'song-2', title: 'Song 2'),
      ];

      final fields = buildExistingFilterableFields(songs);

      expect(fields.containsKey('key'), isFalse);
    });

    test(
      'adds a key filter from Song.keyField and counts populated songs',
      () async {
        final songs = [
          buildSong(uuid: 'song-1', title: 'Song 1', key: 'C-major'),
          buildSong(uuid: 'song-2', title: 'Song 2'),
          buildSong(uuid: 'song-3', title: 'Song 3', key: 'C-major'),
        ];

        final fields = buildExistingFilterableFields(songs);

        expect(fields.containsKey('key'), isTrue);
        expect(fields['key']?.type, equals(FieldType.key));
        expect(fields['key']?.count, equals(2));
      },
    );
  });

  group('matchesKeyFilters', () {
    Song buildSong(String key) {
      return Song.fromBankApiJson({
        'uuid': 'song-$key',
        'title': 'Song $key',
        'lyrics': '<song><lyrics>Song</lyrics></song>',
        'key': key,
      });
    }

    test('matches a complete key even when pitch and mode filters differ', () {
      final song = buildSong('A-dur');
      final keyFilters = (
        pitches: {'H'},
        modes: {'moll'},
        keys: {KeyField('A', 'dur')},
      );

      expect(matchesKeyFilters(song, keyFilters), isTrue);
    });

    test('requires both pitch and mode when partial key filters are used', () {
      final pitchOnlySong = buildSong('A-moll');
      final modeOnlySong = buildSong('H-dur');
      final matchingSong = buildSong('A-dur');
      final KeyFilters keyFilters = (pitches: {'A'}, modes: {'dur'}, keys: {});

      expect(matchesKeyFilters(pitchOnlySong, keyFilters), isFalse);
      expect(matchesKeyFilters(modeOnlySong, keyFilters), isFalse);
      expect(matchesKeyFilters(matchingSong, keyFilters), isTrue);
    });

    test('ORs complete keys with partial key filters', () {
      final song = buildSong('H-moll');
      final keyFilters = (
        pitches: {'A'},
        modes: {'dur'},
        keys: {KeyField('H', 'moll')},
      );

      expect(matchesKeyFilters(song, keyFilters), isTrue);
    });
  });
}
