import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/song_fields.dart';
import 'package:sofarhangolo/services/songs/filter.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/key/state.dart';

import '../harness/test_database.dart';
import '../harness/test_harness.dart' show waitForProviderValue;

typedef FilterFields = Map<String, ({SongField field, int count})>;

void main() {
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

  Song buildSong({
    required String uuid,
    String? title,
    List<String> keys = const [],
    Map<String, Object> extra = const {},
  }) {
    return Song.fromBankApiJson({
      'uuid': uuid,
      'title': title ?? 'Song $uuid',
      'lyrics': '[V1]\n Hello $uuid',
      if (keys.isNotEmpty) 'key': keys,
      ...extra,
    });
  }

  Future<void> insertAll(Iterable<Song> songs) async {
    for (final song in songs) {
      await db.into(db.songs).insert(song);
    }
  }

  Future<FilterFields> existingFields([Map<String, SongField>? registry]) =>
      buildExistingFilterableFields(registry).first;

  group('buildExistingFilterableFields', () {
    test('counts text and list fields with a filter use', () async {
      await insertAll([
        buildSong(
          uuid: 'song-1',
          extra: {
            'genre': ['Rock', 'Pop'],
            'language': 'magyar',
            'composer': 'Composer A',
          },
        ),
        buildSong(
          uuid: 'song-2',
          extra: {
            'genre': ['Rock'],
          },
        ),
      ]);

      final fields = await existingFields();

      expect(fields['genre']?.field.title, 'Stílus / műfaj');
      expect(fields['genre']?.count, equals(2));
      expect(fields['language']?.count, equals(1));
      // No filter use in the default registry.
      expect(fields['composer'], isNull);
      expect(fields.containsKey('unknown_field'), isFalse);
    });

    test('does not count blank values or empty list elements', () async {
      await insertAll([
        buildSong(
          uuid: 'song-1',
          extra: {
            'genre': [' '],
            'language': '',
          },
        ),
        buildSong(uuid: 'song-2', extra: {'genre': [], 'language': '   '}),
        buildSong(
          uuid: 'song-3',
          extra: {
            'genre': ['', 'Rock'],
          },
        ),
      ]);

      final fields = await existingFields();

      // Only song-3 has a non-blank genre element; language is blank on all.
      expect(fields['genre']?.count, equals(1));
      expect(fields['language'], isNull);
    });

    test(
      'adds a key filter from key_field and counts populated songs',
      () async {
        await insertAll([
          buildSong(uuid: 'song-1', keys: ['C-major']),
          buildSong(uuid: 'song-2'),
          buildSong(uuid: 'song-3', keys: ['A-moll', 'C-major']),
        ]);

        final fields = await existingFields();

        expect(fields.containsKey('key'), isTrue);
        expect(fields['key']?.field.core, isTrue);
        expect(fields['key']?.count, equals(2));
      },
    );

    test('omits the key filter when no songs have a key', () async {
      await insertAll([buildSong(uuid: 'song-1'), buildSong(uuid: 'song-2')]);

      final fields = await existingFields();

      expect(fields.containsKey('key'), isFalse);
    });

    test('recomputes when the songs table changes', () async {
      await insertAll([
        buildSong(uuid: 'song-1', extra: {'language': 'magyar'}),
      ]);

      final iterator = StreamIterator(buildExistingFilterableFields());
      addTearDown(iterator.cancel);
      await iterator.moveNext();
      expect(iterator.current['language']?.count, equals(1));

      await insertAll([
        buildSong(uuid: 'song-2', extra: {'language': 'angol'}),
      ]);
      await iterator.moveNext();
      expect(iterator.current['language']?.count, equals(2));
    });
  });

  group('buildExistingFilterableFields with registry', () {
    test('counts fields the overlay registry grants a filter use', () async {
      final registry = mergeSongFields(defaultSongFieldRegistry, {
        'orchestra': {
          'title': 'Zenekar',
          'type': 'list',
          'uses': ['details', 'filter_multiselect'],
        },
      });
      await insertAll([
        buildSong(
          uuid: 's1',
          extra: {
            'orchestra': ['Big Band'],
            'genre': ['Rock'],
          },
        ),
      ]);

      final fields = await existingFields(registry);

      expect(fields['orchestra']?.field.title, 'Zenekar');
      expect(
        fields['orchestra']?.field.filterUse,
        SongFieldUse.filterMultiselect,
      );
      expect(fields['orchestra']?.count, equals(1));
      // Defaults keep working alongside the overlay field.
      expect(fields['genre']?.count, equals(1));
    });

    test('drops fields whose def lost its filter use in an overlay', () async {
      final registry = mergeSongFields(defaultSongFieldRegistry, {
        'genre': {
          'uses': ['details'],
        },
      });
      await insertAll([
        buildSong(
          uuid: 's1',
          extra: {
            'genre': ['Rock'],
          },
        ),
      ]);

      expect((await existingFields(registry))['genre'], isNull);
      // The base registry is untouched: overlay merge returns a new map.
      expect((await existingFields())['genre']?.count, equals(1));
    });
  });

  group('existingFilterableFields provider', () {
    Future<void> until(bool Function() predicate) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!predicate()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('condition not reached before timeout');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('recomputes when the songs table changes', () async {
      await insertAll([
        buildSong(uuid: 'song-1', extra: {'language': 'magyar'}),
      ]);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final values = <FilterFields>[];
      container.listen(existingFilterableFieldsProvider, (previous, next) {
        if (next.hasValue) values.add(next.value!);
      }, fireImmediately: true);

      await until(() => values.isNotEmpty);
      expect(values.last['language']?.count, equals(1));

      await insertAll([
        buildSong(uuid: 'song-2', extra: {'language': 'angol'}),
      ]);
      await until(() => values.length >= 2);
      expect(values.last['language']?.count, equals(2));
    });

    test('merges bank overlays over the default registry', () async {
      await db
          .into(db.banks)
          .insert(
            BanksCompanion.insert(
              uuid: 'bank-1',
              name: 'Test Bank',
              baseUrl: Uri.parse('https://example.com/api'),
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
    Song buildKeySong(String key) {
      return buildSong(uuid: 'song-$key', keys: [key]);
    }

    test('matches a complete key even when pitch and mode filters differ', () {
      final song = buildKeySong('A-dur');
      final keyFilters = (
        pitches: {'H'},
        modes: {'moll'},
        keys: {KeyField('A', 'dur')},
      );

      expect(matchesKeyFilters(song, keyFilters), isTrue);
    });

    test('requires both pitch and mode when partial key filters are used', () {
      final pitchOnlySong = buildKeySong('A-moll');
      final modeOnlySong = buildKeySong('H-dur');
      final matchingSong = buildKeySong('A-dur');
      final KeyFilters keyFilters = (pitches: {'A'}, modes: {'dur'}, keys: {});

      expect(matchesKeyFilters(pitchOnlySong, keyFilters), isFalse);
      expect(matchesKeyFilters(modeOnlySong, keyFilters), isFalse);
      expect(matchesKeyFilters(matchingSong, keyFilters), isTrue);
    });

    test('ORs complete keys with partial key filters', () {
      final song = buildKeySong('H-moll');
      final keyFilters = (
        pitches: {'A'},
        modes: {'dur'},
        keys: {KeyField('H', 'moll')},
      );

      expect(matchesKeyFilters(song, keyFilters), isTrue);
    });
  });
}
