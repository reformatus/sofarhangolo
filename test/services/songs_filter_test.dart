import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/song_fields.dart';
import 'package:sofarhangolo/services/songs/filter.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/key/state.dart';

import '../harness/test_database.dart';
import '../harness/test_harness.dart' show waitForProviderValue;

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
        'lyrics': '[V1]\n Hello $title',
        'key': key == null ? null : [key],
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
        expect(fields['key']?.field.core, isTrue);
        expect(fields['key']?.count, equals(2));
      },
    );

    test('counts list and text fields with a filter use', () {
      final songs = [
        buildSong(
          uuid: 'song-1',
          title: 'Song 1',
          extra: {
            'genre': ['Rock'],
            'language': 'magyar',
            'composer': 'Composer A',
          },
        ),
      ];

      final fields = buildExistingFilterableFields(songs);

      expect(fields['genre']?.field.title, 'Stílus / műfaj');
      expect(fields['genre']?.count, equals(1));
      expect(fields['language']?.count, equals(1));
      // No filter use in the default registry.
      expect(fields['composer'], isNull);
      expect(fields.containsKey('unknown_field'), isFalse);
    });

    test('skips blank content', () {
      final songs = [
        buildSong(
          uuid: 'song-1',
          title: 'Song 1',
          extra: {
            'genre': [' '],
            'language': '',
          },
        ),
      ];

      final fields = buildExistingFilterableFields(songs);

      expect(fields['genre'], isNull);
      expect(fields['language'], isNull);
    });
  });

  group('buildExistingFilterableFields with registry', () {
    Song buildSong(String uuid, Map<String, Object> extra) {
      return Song.fromBankApiJson({
        'uuid': uuid,
        'title': 'Song $uuid',
        'lyrics': '[V1]\n Hello Song',
        ...extra,
      });
    }

    test('counts fields the overlay registry grants a filter use', () {
      final registry = mergeSongFields(defaultSongFieldRegistry, {
        'orchestra': {
          'title': 'Zenekar',
          'type': 'list',
          'uses': ['details', 'filter_multiselect'],
        },
      });
      final songs = [
        buildSong('s1', {
          'orchestra': ['Big Band'],
          'genre': ['Rock'],
        }),
      ];

      final fields = buildExistingFilterableFields(songs, registry);

      expect(fields['orchestra']?.field.title, 'Zenekar');
      expect(
        fields['orchestra']?.field.filterUse,
        SongFieldUse.filterMultiselect,
      );
      expect(fields['orchestra']?.count, equals(1));
      // Defaults keep working alongside the overlay field.
      expect(fields['genre']?.count, equals(1));
    });

    test('drops fields whose def lost its filter use in an overlay', () {
      final registry = mergeSongFields(defaultSongFieldRegistry, {
        'genre': {
          'uses': ['details'],
        },
      });
      final songs = [
        buildSong('s1', {
          'genre': ['Rock'],
        }),
      ];

      expect(buildExistingFilterableFields(songs, registry)['genre'], isNull);
      // The base registry is untouched: overlay merge returns a new map.
      expect(buildExistingFilterableFields(songs)['genre']?.count, equals(1));
    });
  });

  group('existingFilterableFields provider', () {
    late LyricDatabase testDb;

    setUp(() async {
      testDb = createTestDatabase();
      db = testDb;
      // Same as songs_update_test: the songs→banks FK is unusable with
      // in-memory schemas, and these tests do not rely on it.
      await testDb.customStatement('PRAGMA foreign_keys = OFF');
    });

    tearDown(() async {
      await testDb.close();
    });

    test('merges bank overlays over the default registry', () async {
      await db
          .into(db.banks)
          .insert(
            BanksCompanion.insert(
              uuid: 'bank-1',
              name: 'Test Bank',
              baseUrl: Value(Uri.parse('https://example.com/api')),
              parallelUpdateJobs: 1,
              amountOfSongsInRequest: 1,
              noCms: false,
              songFields: {
                'orchestra': {
                  'title': 'Zenekar',
                  'type': 'list',
                  'uses': ['details', 'filter_multiselect'],
                },
              },
              isEnabled: true,
              isOfflineMode: false,
            ),
          );
      await db
          .into(db.songs)
          .insert(
            Song.fromBankApiJson({
              'uuid': 'song-1',
              'title': 'Song 1',
              'lyrics': '[V1]\n Hello Song',
              'orchestra': ['Big Band'],
              'genre': ['Rock'],
            }),
          );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final fields = await waitForProviderValue(
        container,
        existingFilterableFieldsProvider,
      );

      expect(fields['orchestra']?.field.title, 'Zenekar');
      expect(fields['orchestra']?.count, equals(1));
      expect(fields['genre']?.count, equals(1));
    });
  });

  group('matchesKeyFilters', () {
    Song buildSong(String key) {
      return Song.fromBankApiJson({
        'uuid': 'song-$key',
        'title': 'Song $key',
        'lyrics': '[V1]\n Hello Song',
        'key': [key],
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
