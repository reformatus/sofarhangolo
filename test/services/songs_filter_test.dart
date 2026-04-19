import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/filter.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/field_type.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/key/state.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/search/state.dart';

import '../harness/test_database.dart';

void main() {
  group('songs filter services', () {
    late LyricDatabase testDb;
    late ProviderContainer container;

    setUp(() async {
      testDb = createTestDatabase();
      db = testDb;
      await db.customStatement('PRAGMA foreign_keys = OFF');
      container = ProviderContainer();

      await db
          .into(db.banks)
          .insert(
            BanksCompanion.insert(
              uuid: 'bank-1',
              name: 'Test Bank',
              baseUrl: Uri.parse('https://example.com/api'),
              parallelUpdateJobs: 1,
              amountOfSongsInRequest: 10,
              noCms: false,
              songFields: {},
              isEnabled: true,
              isOfflineMode: false,
            ),
          );
    });

    tearDown(() async {
      container.dispose();
      await testDb.close();
    });

    Future<void> insertSongs(Iterable<Map<String, dynamic>> jsonSongs) async {
      final bank = await db.select(db.banks).getSingle();
      for (final jsonSong in jsonSongs) {
        await db
            .into(db.songs)
            .insert(Song.fromBankApiJson(jsonSong, sourceBank: bank));
      }
    }

    Future<T> readAsyncValue<T>(dynamic provider) async {
      final completer = Completer<T>();
      late final ProviderSubscription<AsyncValue<T>> subscription;

      subscription = container.listen(provider, (_, next) {
        next.when(
          data: (value) {
            if (completer.isCompleted) return;
            completer.complete(value);
            subscription.close();
          },
          error: (error, stackTrace) {
            if (completer.isCompleted) return;
            completer.completeError(error, stackTrace);
            subscription.close();
          },
          loading: () {},
        );
      }, fireImmediately: true);

      return completer.future;
    }

    test(
      'existing filterable fields count key values from content_map',
      () async {
        await insertSongs([
          {
            'uuid': 'song-1',
            'title': 'Song 1',
            'lyrics': 'Lyrics 1',
            'key': 'C-major',
          },
          {'uuid': 'song-2', 'title': 'Song 2', 'lyrics': 'Lyrics 2'},
          {
            'uuid': 'song-3',
            'title': 'Song 3',
            'lyrics': 'Lyrics 3',
            'key': 'G-major',
          },
        ]);

        final fields = await readAsyncValue(existingFilterableFieldsProvider);

        expect(fields['key']?.type, FieldType.key);
        expect(fields['key']?.count, 2);
      },
    );

    test(
      'selectable values are split in SQLite for comma-delimited filters',
      () async {
        await insertSongs([
          {
            'uuid': 'song-1',
            'title': 'Song 1',
            'lyrics': 'Lyrics 1',
            'genre': 'Praise, Worship',
          },
          {
            'uuid': 'song-2',
            'title': 'Song 2',
            'lyrics': 'Lyrics 2',
            'genre': 'Worship, Advent',
          },
        ]);

        final values = await readAsyncValue(
          selectableValuesForFilterableFieldProvider(
            'genre',
            FieldType.multiselectTags,
          ),
        );

        expect(values, ['Advent', 'Praise', 'Worship']);
      },
    );

    test('short search terms still match title through LIKE search', () async {
      await insertSongs([
        {'uuid': 'song-1', 'title': 'Grace Alone', 'lyrics': 'Amazing grace'},
      ]);

      container.read(searchStringStateProvider.notifier).set('Gr');

      final results = await readAsyncValue(filteredSongsProvider);

      expect(results.map((result) => result.song.uuid), ['song-1']);
    });

    test(
      'dynamic searchable bank fields are searched through SQLite LIKE',
      () async {
        await insertSongs([
          {
            'uuid': 'song-1',
            'title': 'Untitled',
            'lyrics': 'No composer in lyrics',
            'composer': 'John Newton',
          },
        ]);

        container.read(searchStringStateProvider.notifier).set('Newton');

        final results = await readAsyncValue(filteredSongsProvider);

        expect(results.map((result) => result.song.uuid), ['song-1']);
      },
    );

    test('key filters operate from content_map data in SQLite', () async {
      await insertSongs([
        {
          'uuid': 'song-1',
          'title': 'Song A',
          'lyrics': 'Lyrics A',
          'key': 'A-dur',
        },
        {
          'uuid': 'song-2',
          'title': 'Song B',
          'lyrics': 'Lyrics B',
          'key': 'H-moll',
        },
      ]);

      final keyFilter = container.read(keyFilterStateProvider.notifier);
      keyFilter.setPitchTo('H', true);
      keyFilter.setModeTo('moll', true);
      keyFilter.setKeyTo(KeyField('A', 'dur'), true);

      final results = await readAsyncValue(filteredSongsProvider);

      expect(results.map((result) => result.song.uuid), ['song-1', 'song-2']);
    });
  });
}
