import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/facet.dart';
import 'package:sofarhangolo/services/songs/filter.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/key/state.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/multiselect-tags/state.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/search/state.dart';

import '../harness/test_database.dart';
import '../harness/test_harness.dart' show waitForProviderValue;

/// Filter state pinned to fixed values for a test.
class FixedTagsFilterState extends MultiselectTagsFilterState {
  FixedTagsFilterState(this.value);

  final Map<String, List<String>> value;

  @override
  Map<String, List<String>> build() => value;
}

class FixedKeyFilterState extends KeyFilterState {
  FixedKeyFilterState(this.value);

  final KeyFilters value;

  @override
  KeyFilters build() => value;
}

class FixedSearchStringState extends SearchStringState {
  FixedSearchStringState(this.value);

  final String value;

  @override
  String build() => value;
}

/// Which filter values still match the query. The load-bearing rule is
/// self-exclusion: a field's own selection must not hide its siblings.
void main() {
  late LyricDatabase testDb;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    // The songs→banks FK is unusable with in-memory schemas; unused here.
    await testDb.customStatement('PRAGMA foreign_keys = OFF');
  });

  tearDown(() async {
    await testDb.close();
  });

  Song song(
    String uuid, {
    required String title,
    List<String> genre = const [],
    String? language,
    List<String> holiday = const [],
    List<String> keys = const [],
    String? bank,
  }) {
    return Song(
      uuid: uuid,
      title: title,
      lyrics: '[V1]\n $title',
      keyField: [for (final key in keys) KeyField.fromString(key)!],
      sourceBank: bank,
      contentMap: {
        if (genre.isNotEmpty) 'genre': genre,
        'language': ?language,
        if (holiday.isNotEmpty) 'holiday': holiday,
      },
    );
  }

  Future<void> insert(Iterable<Song> songs) =>
      db.batch((batch) => batch.insertAll(db.songs, songs));

  ProviderContainer containerFor({
    Map<String, List<String>> filters = const {},
    String search = '',
    KeyFilters keyFilters = noKeyFilters,
  }) {
    final container = ProviderContainer(
      overrides: [
        // No waiting in tests.
        facetDebounceDurationProvider.overrideWithValue(Duration.zero),
        multiselectTagsFilterStateProvider.overrideWith(
          () => FixedTagsFilterState(filters),
        ),
        keyFilterStateProvider.overrideWith(
          () => FixedKeyFilterState(keyFilters),
        ),
        searchStringStateProvider.overrideWith(
          () => FixedSearchStringState(search),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<Set<String>> values(
    String field, {
    Map<String, List<String>> filters = const {},
    String search = '',
    KeyFilters keyFilters = noKeyFilters,
  }) => waitForProviderValue(
    containerFor(filters: filters, search: search, keyFilters: keyFilters),
    fieldFacetProvider(field),
  );

  Future<AvailableKeys> keys({
    Map<String, List<String>> filters = const {},
    String search = '',
    KeyFilters keyFilters = noKeyFilters,
  }) => waitForProviderValue(
    containerFor(filters: filters, search: search, keyFilters: keyFilters),
    keyFacetProvider,
  );

  Future<Set<String>> banks({
    Map<String, List<String>> filters = const {},
    KeyFilters keyFilters = noKeyFilters,
  }) => waitForProviderValue(
    containerFor(filters: filters, keyFilters: keyFilters),
    bankFacetProvider,
  );

  group('field facets', () {
    test('offer the values the songs carry, split and sorted', () async {
      await insert([
        song('s1', title: 'Alpha', genre: ['Rock', 'Pop'], language: 'magyar'),
        song('s2', title: 'Beta', genre: ['Jazz'], language: 'angol'),
      ]);

      expect(await values('genre'), {'Jazz', 'Pop', 'Rock'});
      expect(await values('language'), {'angol', 'magyar'});
    });

    test('drop blanks and empty list elements', () async {
      await insert([
        song('s1', title: 'Alpha', genre: [' ', 'Rock', ''], language: '   '),
      ]);

      expect(await values('genre'), {'Rock'});
      expect(await values('language'), isEmpty);
    });

    test('a field\'s own selection does not hide its siblings', () async {
      await insert([
        song('s1', title: 'Alpha', genre: ['Rock']),
        song('s2', title: 'Beta', genre: ['Pop']),
        song('s3', title: 'Gamma', genre: ['Jazz']),
      ]);

      // Rock is selected, yet the other genres stay selectable.
      expect(
        await values(
          'genre',
          filters: {
            'genre': ['Rock'],
          },
        ),
        {'Rock', 'Pop', 'Jazz'},
      );
    });

    test('another field\'s selection narrows the options', () async {
      await insert([
        song('s1', title: 'Alpha', genre: ['Rock'], holiday: ['Karácsony']),
        song('s2', title: 'Beta', genre: ['Pop']),
      ]);

      // The holiday song is a Rock song, so Rock keeps it available...
      expect(
        await values(
          'holiday',
          filters: {
            'genre': ['Rock'],
          },
        ),
        {'Karácsony'},
      );
      // ...and Pop has no holiday song at all.
      expect(
        await values(
          'holiday',
          filters: {
            'genre': ['Pop'],
          },
        ),
        isEmpty,
      );
    });

    test('the search term narrows the options', () async {
      await insert([
        song('s1', title: 'Alpha', genre: ['Rock'], language: 'magyar'),
        song('s2', title: 'Gamma', genre: ['Jazz'], language: 'angol'),
      ]);

      expect(await values('genre', search: 'gamma'), {'Jazz'});
      expect(await values('language', search: 'gamma'), {'angol'});
    });
  });

  group('key facet', () {
    test('splits keys into pitches, modes and complete keys', () async {
      await insert([
        song('s1', title: 'Alpha', keys: ['C-dúr']),
        song('s2', title: 'Beta', keys: ['A-moll']),
        song('s3', title: 'Gamma', keys: ['C-dúr', 'A-moll']),
      ]);

      final available = await keys();

      expect(available.keys, {KeyField('C', 'dúr'), KeyField('A', 'moll')});
      expect(available.pitches, {'A', 'C'});
      expect(available.modes, {'dúr', 'moll'});
    });

    test(
      'is narrowed by the other fields but not by its own selection',
      () async {
        await insert([
          song('s1', title: 'Alpha', genre: ['Rock'], keys: ['C-dúr']),
          song('s2', title: 'Beta', genre: ['Pop'], keys: ['A-moll']),
        ]);

        // Rock only has C, so A disappears - even with a key selected.
        final narrowed = await keys(
          filters: {
            'genre': ['Rock'],
          },
          keyFilters: (pitches: {'A'}, modes: <String>{}, keys: <KeyField>{}),
        );
        expect(narrowed.keys, {KeyField('C', 'dúr')});
      },
    );
  });

  group('bank facet', () {
    test('drops banks the current query cannot reach', () async {
      await insert([
        song('s1', title: 'Alpha', genre: ['Rock'], bank: 'bank-1'),
        song('s2', title: 'Beta', genre: ['Pop'], bank: 'bank-2'),
      ]);

      expect(await banks(), {'bank-1', 'bank-2'});
      expect(
        await banks(
          filters: {
            'genre': ['Rock'],
          },
        ),
        {'bank-1'},
      );
    });
  });
}
