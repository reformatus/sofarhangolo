import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/song_fields.dart';

void main() {
  group('SongFieldUse', () {
    test('marks exactly the filter-card uses', () {
      expect(SongFieldUse.filterMultiselect.isFilterUse, isTrue);
      expect(SongFieldUse.filterKey.isFilterUse, isTrue);
      expect(SongFieldUse.details.isFilterUse, isFalse);
      expect(SongFieldUse.summary.isFilterUse, isFalse);
    });

    test('marks exactly the search uses', () {
      expect(SongFieldUse.searchText.isSearchUse, isTrue);
      expect(SongFieldUse.searchBible.isSearchUse, isTrue);
      expect(SongFieldUse.searchSongbook.isSearchUse, isTrue);
      for (final use in [
        SongFieldUse.filterMultiselect,
        SongFieldUse.filterKey,
        SongFieldUse.details,
        SongFieldUse.summary,
      ]) {
        expect(use.isSearchUse, isFalse, reason: use.name);
      }
    });
  });

  group('SongSearchGroup', () {
    test('weights follow the agreed relevance ladder', () {
      expect(SongSearchGroup.title.weight, 10.0);
      expect(SongSearchGroup.people.weight, 5.0);
      expect(SongSearchGroup.metadata.weight, 2.0);
      expect(SongSearchGroup.lyrics.weight, 1.0);
      expect(
        SongSearchGroup.title.weight,
        greaterThan(SongSearchGroup.people.weight),
      );
      expect(
        SongSearchGroup.people.weight,
        greaterThan(SongSearchGroup.metadata.weight),
      );
      expect(
        SongSearchGroup.metadata.weight,
        greaterThan(SongSearchGroup.lyrics.weight),
      );
    });
  });

  group('SongField', () {
    test('filterUse resolves the single filter-card use', () {
      expect(
        defaultSongFieldRegistry['key']!.filterUse,
        SongFieldUse.filterKey,
      );
      expect(
        defaultSongFieldRegistry['genre']!.filterUse,
        SongFieldUse.filterMultiselect,
      );
      expect(defaultSongFieldRegistry['composer']!.filterUse, isNull);
      expect(defaultSongFieldRegistry['composer']!.hasFilterUse, isFalse);
      expect(defaultSongFieldRegistry['key']!.hasFilterUse, isTrue);
    });

    test('hasSearchUse resolves search participation', () {
      expect(defaultSongFieldRegistry['title']!.hasSearchUse, isTrue);
      expect(defaultSongFieldRegistry['composer']!.hasSearchUse, isTrue);
      expect(defaultSongFieldRegistry['genre']!.hasSearchUse, isFalse);
      expect(defaultSongFieldRegistry['key']!.hasSearchUse, isFalse);
    });
  });

  group('SongField.fromJson', () {
    test('parses type aliases into list', () {
      for (final type in ['list', 'array', 'tags']) {
        expect(
          SongField.fromJson('f', {'type': type}).type,
          SongFieldType.list,
          reason: type,
        );
      }
      expect(SongField.fromJson('f', {}).type, SongFieldType.text);
      expect(
        SongField.fromJson('f', {'type': 'TEXT'}).type,
        SongFieldType.text,
      );
    });

    test('parses the known use names and ignores unknown ones', () {
      final field = SongField.fromJson('f', {
        'uses': [
          'filter_multiselect',
          'filter_key',
          'details',
          'summary',
          'nonsense',
        ],
      });

      expect(field.uses, {
        SongFieldUse.filterMultiselect,
        SongFieldUse.filterKey,
        SongFieldUse.details,
        SongFieldUse.summary,
      });
    });

    test('ignores a non-list uses value', () {
      expect(SongField.fromJson('f', {'uses': 'details'}).uses, isEmpty);
    });

    test('parses search_group and degrades unknown values', () {
      expect(
        SongField.fromJson('f', {'search_group': 'people'}).searchGroup,
        SongSearchGroup.people,
      );
      expect(
        SongField.fromJson('f', {'search_group': 'METADATA'}).searchGroup,
        SongSearchGroup.metadata,
      );
      expect(
        SongField.fromJson('f', {'search_group': 'nonsense'}).searchGroup,
        isNull,
      );
      expect(SongField.fromJson('f', {}).searchGroup, isNull);
      expect(SongField.fromJson('f', {'search_group': 7}).searchGroup, isNull);
    });

    test('falls back to the api name as title', () {
      expect(SongField.fromJson('orchestra', {}).title, 'orchestra');
      expect(
        SongField.fromJson('orchestra', {'title': 'Zenekar'}).title,
        'Zenekar',
      );
    });

    test('degrades non-string title and type instead of throwing', () {
      final field = SongField.fromJson('orchestra', {
        'title': 123,
        'type': ['list'],
      });

      expect(field.title, 'orchestra');
      expect(field.type, SongFieldType.text);
    });
  });

  group('defaultSongFields', () {
    test('registry keys are unique and cover every default field', () {
      expect(
        defaultSongFieldRegistry.length,
        defaultSongFields.length,
        reason: 'api names must be unique',
      );
      expect(
        defaultSongFieldRegistry.keys,
        containsAll(defaultSongFields.map((field) => field.apiName)),
      );
    });

    test('core fields stay core', () {
      for (final name in [
        'uuid',
        'title',
        'lyrics',
        'key',
        'variation_of',
        'pdf',
        'svg',
      ]) {
        expect(defaultSongFieldRegistry[name]!.core, isTrue, reason: name);
      }
    });

    test('search fields carry ranking groups', () {
      const groups = {
        'title': SongSearchGroup.title,
        'lyrics': SongSearchGroup.lyrics,
        'composer': SongSearchGroup.people,
        'lyricist': SongSearchGroup.people,
        'translator': SongSearchGroup.people,
        'title_original': SongSearchGroup.metadata,
        'bible_ref': SongSearchGroup.metadata,
        'songbook': SongSearchGroup.metadata,
      };
      for (final entry in groups.entries) {
        final field = defaultSongFieldRegistry[entry.key]!;
        expect(field.hasSearchUse, isTrue, reason: entry.key);
        expect(field.searchGroup, entry.value, reason: entry.key);
      }
      // Every search-use field needs a group: the FTS weight vector uses them.
      for (final field in defaultSongFields) {
        if (field.hasSearchUse) {
          expect(field.searchGroup, isNotNull, reason: field.apiName);
        }
      }
    });
  });

  group('mergeSongFields', () {
    test('returns the base registry unchanged for an empty overlay', () {
      expect(
        mergeSongFields(defaultSongFieldRegistry, {}),
        same(defaultSongFieldRegistry),
      );
    });

    test('never overrides core fields', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'title': {
          'title': 'Megszerezve',
          'uses': ['details'],
        },
      });

      expect(merged['title']!.title, 'Cím');
      expect(merged['title']!.core, isTrue);
    });

    test('adds new fields with overlay uses and no app icon', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'orchestra': {
          'title': 'Zenekar',
          'type': 'list',
          'uses': ['details', 'filter_multiselect'],
        },
      });

      final orchestra = merged['orchestra']!;
      expect(orchestra.title, 'Zenekar');
      expect(orchestra.type, SongFieldType.list);
      expect(orchestra.icon, isNull);
      expect(orchestra.core, isFalse);
      expect(orchestra.uses, {
        SongFieldUse.details,
        SongFieldUse.filterMultiselect,
      });
    });

    test('customizes non-core fields but keeps the app icon', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'genre': {
          'uses': ['details'],
        },
      });

      final genre = merged['genre']!;
      expect(genre.uses, {SongFieldUse.details});
      expect(genre.filterUse, isNull);
      expect(genre.icon, defaultSongFieldRegistry['genre']!.icon);
    });

    test('keeps the base title and type when the overlay omits them', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'genre': {
          'uses': ['details'],
        },
      });

      final genre = merged['genre']!;
      expect(genre.title, 'Stílus / műfaj');
      expect(genre.type, SongFieldType.list);
    });

    test('keeps the base title and type for non-string overlay values', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'genre': {
          'title': 7,
          'type': 7,
          'uses': ['details'],
        },
      });

      final genre = merged['genre']!;
      expect(genre.title, 'Stílus / műfaj');
      expect(genre.type, SongFieldType.list);
    });

    test('lets an overlay override the title and type', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'genre': {
          'title': 'Műfaj',
          'type': 'text',
          'uses': ['details'],
        },
      });

      expect(merged['genre']!.title, 'Műfaj');
      expect(merged['genre']!.type, SongFieldType.text);
    });

    test('strips filter_key from overlays', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'genre': {
          'uses': ['filter_key', 'details'],
        },
      });

      expect(merged['genre']!.uses, {SongFieldUse.details});
    });

    test('keeps base search uses and group when an overlay customizes a field', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'composer': {
          'title': 'Szerző',
          'uses': ['details'],
          'search_group': 'lyrics',
        },
      });

      final composer = merged['composer']!;
      expect(composer.hasSearchUse, isTrue);
      expect(composer.uses.contains(SongFieldUse.searchText), isTrue);
      expect(composer.searchGroup, SongSearchGroup.people);
    });

    test('keeps a declared search group on overlay-introduced fields', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'orchestra': {
          'search_group': 'people',
          'uses': ['details'],
        },
      });

      final orchestra = merged['orchestra']!;
      expect(orchestra.searchGroup, SongSearchGroup.people);
      // Inert: overlay fields are not searchable, but the group carries over.
      expect(orchestra.hasSearchUse, isFalse);
    });

    test('skips malformed overlay entries', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'broken': 'not a map',
      });

      expect(merged.containsKey('broken'), isFalse);
    });
  });
}
