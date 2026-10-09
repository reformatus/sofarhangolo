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

    test('falls back to the api name as title', () {
      expect(SongField.fromJson('orchestra', {}).title, 'orchestra');
      expect(
        SongField.fromJson('orchestra', {'title': 'Zenekar'}).title,
        'Zenekar',
      );
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

    test('strips filter_key from overlays', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'genre': {
          'uses': ['filter_key', 'details'],
        },
      });

      expect(merged['genre']!.uses, {SongFieldUse.details});
    });

    test('skips malformed overlay entries', () {
      final merged = mergeSongFields(defaultSongFieldRegistry, {
        'broken': 'not a map',
      });

      expect(merged.containsKey('broken'), isFalse);
    });
  });
}
