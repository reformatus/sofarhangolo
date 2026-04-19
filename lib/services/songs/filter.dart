import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';
import '../../ui/base/songs/widgets/filter/types/bank/state.dart';
import '../../ui/base/songs/widgets/filter/types/field_type.dart';
import '../../ui/base/songs/widgets/filter/types/key/state.dart';
import '../../ui/base/songs/widgets/filter/types/multiselect-tags/state.dart';
import '../../ui/base/songs/widgets/filter/types/search/state.dart';
import 'field_registry.dart';

part 'filter.g.dart';

const List<String> fullTextSearchFields = ['title', 'lyrics'];
const snippetTags = (start: '<?', end: '?>');

typedef SongFieldPopulation = ({FieldType type, int count});
typedef _SqlFragment = ({String sql, List<Variable> variables});

String sanitizeFts(String value) => sanitize(value);

String escapeLikePattern(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

String _placeholders(int count) => List.filled(count, '?').join(', ');

_SqlFragment _bankScopeClause(
  Set<String> bankFilters, {
  String songAlias = 'songs',
}) {
  if (bankFilters.isEmpty) {
    return (sql: '1 = 1', variables: const []);
  }

  return (
    sql: '$songAlias.source_bank IN (${_placeholders(bankFilters.length)})',
    variables: bankFilters.map((bank) => Variable<String>(bank)).toList(),
  );
}

_SqlFragment _filterClause(
  Map<String, List<String>> filters,
  SongFieldCatalog catalog, {
  String songAlias = 'songs',
}) {
  if (filters.isEmpty) {
    return (sql: '1 = 1', variables: const []);
  }

  final clauses = <String>[];
  final variables = <Variable>[];

  for (final entry in filters.entries) {
    final definition = catalog[entry.key];
    if (definition == null || entry.value.isEmpty) continue;

    final jsonPath = '\$.${entry.key}';
    if (definition.commaDividedValues) {
      final tokenClauses = <String>[];
      for (final value in entry.value) {
        tokenClauses.add(
          "(',' || REPLACE(TRIM(COALESCE(json_extract($songAlias.content_map, ?), '')), ', ', ',') || ',') LIKE ? ESCAPE '\\'",
        );
        variables.add(Variable<String>(jsonPath));
        variables.add(
          Variable<String>('%,${escapeLikePattern(value.trim())},%'),
        );
      }
      clauses.add('(${tokenClauses.join(' OR ')})');
    } else {
      clauses.add(
        "TRIM(COALESCE(json_extract($songAlias.content_map, ?), '')) IN (${_placeholders(entry.value.length)})",
      );
      variables.add(Variable<String>(jsonPath));
      variables.addAll(
        entry.value.map((value) => Variable<String>(value.trim())),
      );
    }
  }

  if (clauses.isEmpty) {
    return (sql: '1 = 1', variables: const []);
  }

  return (sql: clauses.join(' AND '), variables: variables);
}

_SqlFragment _keyClause(KeyFilters keyFilters, {String songAlias = 'songs'}) {
  if (keyFilters.isEmpty) {
    return (sql: '1 = 1', variables: const []);
  }

  final variables = <Variable>[];
  final clauses = <String>[];
  final keyValuesCte =
      '''
    WITH RECURSIVE key_source(value, rest) AS (
      SELECT '', TRIM(COALESCE(json_extract($songAlias.content_map, '\$.key'), '')) || ','
      UNION ALL
      SELECT
        TRIM(SUBSTR(rest, 1, INSTR(rest, ',') - 1)),
        LTRIM(SUBSTR(rest, INSTR(rest, ',') + 1))
      FROM key_source
      WHERE rest <> ''
    )
    SELECT 1
    FROM key_source
    WHERE value <> ''
      AND INSTR(value, '-') > 0
  ''';

  if (keyFilters.keys.isNotEmpty) {
    clauses.add('''
      EXISTS (
        $keyValuesCte
          AND value IN (${_placeholders(keyFilters.keys.length)})
      )
      ''');
    variables.addAll(
      keyFilters.keys.map((key) => Variable<String>(key.toString())),
    );
  }

  if (keyFilters.pitches.isNotEmpty || keyFilters.modes.isNotEmpty) {
    final partialPredicates = <String>[];
    if (keyFilters.pitches.isNotEmpty) {
      partialPredicates.add(
        "SUBSTR(value, 1, INSTR(value, '-') - 1) IN (${_placeholders(keyFilters.pitches.length)})",
      );
      variables.addAll(
        keyFilters.pitches.map((pitch) => Variable<String>(pitch)),
      );
    }
    if (keyFilters.modes.isNotEmpty) {
      partialPredicates.add(
        "SUBSTR(value, INSTR(value, '-') + 1) IN (${_placeholders(keyFilters.modes.length)})",
      );
      variables.addAll(keyFilters.modes.map((mode) => Variable<String>(mode)));
    }

    clauses.add('''
      EXISTS (
        $keyValuesCte
          AND ${partialPredicates.join(' AND ')}
      )
      ''');
  }

  return (sql: '(${clauses.join(' OR ')})', variables: variables);
}

_SqlFragment _searchClause(
  String rawSearchString,
  List<String> searchFields, {
  String songAlias = 'songs',
  String ftsAlias = 'fts',
}) {
  if (rawSearchString.trim().isEmpty || searchFields.isEmpty) {
    return (sql: '1 = 1', variables: const []);
  }

  final likePattern = '%${escapeLikePattern(rawSearchString.trim())}%';
  final variables = <Variable>[];
  final clauses = <String>[];

  if (searchFields.contains('title')) {
    clauses.add("$songAlias.title LIKE ? ESCAPE '\\'");
    variables.add(Variable<String>(likePattern));
  }
  if (searchFields.contains('lyrics')) {
    clauses.add("$songAlias.lyrics LIKE ? ESCAPE '\\'");
    variables.add(Variable<String>(likePattern));
  }

  final dynamicFields = searchFields
      .where((field) => !fullTextSearchFields.contains(field))
      .toList(growable: false);
  if (dynamicFields.isNotEmpty) {
    clauses.add('''
      EXISTS (
        SELECT 1
        FROM json_each($songAlias.content_map) AS search_entry
        WHERE search_entry.key IN (${_placeholders(dynamicFields.length)})
          AND CAST(search_entry.value AS TEXT) LIKE ? ESCAPE '\\'
      )
      ''');
    variables.addAll(dynamicFields.map((field) => Variable<String>(field)));
    variables.add(Variable<String>(likePattern));
  }

  final ftsSanitized = sanitizeFts(rawSearchString.trim());
  if (ftsSanitized.isNotEmpty &&
      searchFields.any(fullTextSearchFields.contains)) {
    clauses.add('$ftsAlias.song_id IS NOT NULL');
  }

  if (clauses.isEmpty) {
    return (sql: '1 = 1', variables: const []);
  }

  return (sql: '(${clauses.join(' OR ')})', variables: variables);
}

String _ftsJoinSql(String rawSearchString, List<String> searchFields) {
  final ftsSanitized = sanitizeFts(rawSearchString.trim());
  if (ftsSanitized.isEmpty ||
      !searchFields.any(fullTextSearchFields.contains)) {
    return '''
      LEFT JOIN (
        SELECT
          NULL AS song_id,
          NULL AS rank,
          NULL AS match_title,
          NULL AS match_lyrics
      ) AS fts ON 1 = 0
    ''';
  }

  return '''
    LEFT JOIN (
      SELECT
        songs_fts.rowid AS song_id,
        bm25(songs_fts, 10.0, 0.5) AS rank,
        snippet(songs_fts, 0, '${snippetTags.start}', '${snippetTags.end}', '...', 30) AS match_title,
        snippet(songs_fts, 1, '${snippetTags.start}', '${snippetTags.end}', '...', 40) AS match_lyrics
      FROM songs_fts
      WHERE songs_fts MATCH ?
    ) AS fts ON fts.song_id = songs.id
  ''';
}

List<Variable> _ftsVariables(
  String rawSearchString,
  List<String> searchFields,
) {
  final ftsSanitized = sanitizeFts(rawSearchString.trim());
  if (ftsSanitized.isEmpty ||
      !searchFields.any(fullTextSearchFields.contains)) {
    return const [];
  }

  return [Variable<String>('{title lyrics} : $ftsSanitized')];
}

SongResult _mapSongResult(QueryRow row) {
  final downloadedAssets = ((row.data['downloaded_assets'] as String?) ?? '')
      .split(',')
      .where((asset) => asset.isNotEmpty)
      .toList(growable: false);

  return SongResult(
    db.songs.map(row.data),
    downloadedAssets: downloadedAssets,
    matchTitle: row.data['match_title'] as String?,
    matchLyrics: row.data['match_lyrics'] as String?,
  );
}

@Riverpod(keepAlive: true)
Stream<Map<String, SongFieldPopulation>> existingFilterableFields(
  Ref ref,
) async* {
  final bankFilters = ref.watch(banksFilterStateProvider);
  final catalog = await ref.watch(activeSongFieldCatalogProvider.future);
  final filterableFields = catalog.filterableFields.toList(growable: false);

  if (filterableFields.isEmpty) {
    yield const {};
    return;
  }

  final bankScope = _bankScopeClause(bankFilters);
  final variables = <Variable>[
    ...bankScope.variables,
    ...filterableFields.map((field) => Variable<String>(field.field)),
  ];

  yield* db
      .customSelect(
        '''
        SELECT entry.key AS field, COUNT(DISTINCT songs.id) AS song_count
        FROM songs, json_each(songs.content_map) AS entry
        WHERE ${bankScope.sql}
          AND entry.key IN (${_placeholders(filterableFields.length)})
          AND TRIM(CAST(entry.value AS TEXT)) <> ''
        GROUP BY entry.key
        ''',
        variables: variables,
        readsFrom: {db.songs},
      )
      .watch()
      .map((rows) {
        final counts = <String, SongFieldPopulation>{};
        for (final row in rows) {
          final field = row.read<String>('field');
          final definition = catalog[field];
          if (definition == null) continue;
          counts[field] = (
            type: definition.type,
            count: row.read<int>('song_count'),
          );
        }
        return counts;
      });
}

@Riverpod(keepAlive: true)
Stream<List<String>> selectableValuesForFilterableField(
  Ref ref,
  String field,
  FieldType fieldType,
) {
  final bankFilters = ref.watch(banksFilterStateProvider);
  final bankScope = _bankScopeClause(bankFilters);
  final variables = <Variable>[...bankScope.variables, Variable<String>(field)];

  final sql = fieldType.commaDividedValues
      ? '''
        WITH RECURSIVE split_values(value, rest) AS (
          SELECT '', TRIM(CAST(entry.value AS TEXT)) || ','
          FROM songs, json_each(songs.content_map) AS entry
          WHERE ${bankScope.sql}
            AND entry.key = ?
            AND TRIM(CAST(entry.value AS TEXT)) <> ''
          UNION ALL
          SELECT
            TRIM(SUBSTR(rest, 1, INSTR(rest, ',') - 1)),
            LTRIM(SUBSTR(rest, INSTR(rest, ',') + 1))
          FROM split_values
          WHERE rest <> ''
        )
        SELECT DISTINCT value
        FROM split_values
        WHERE value <> ''
        ORDER BY value COLLATE NOCASE
      '''
      : '''
        SELECT DISTINCT TRIM(CAST(entry.value AS TEXT)) AS value
        FROM songs, json_each(songs.content_map) AS entry
        WHERE ${bankScope.sql}
          AND entry.key = ?
          AND TRIM(CAST(entry.value AS TEXT)) <> ''
        ORDER BY value COLLATE NOCASE
      ''';

  return db
      .customSelect(sql, variables: variables, readsFrom: {db.songs})
      .watch()
      .map((rows) => rows.map((row) => row.read<String>('value')).toList());
}

@Riverpod(keepAlive: true)
Stream<List<SongResult>> filteredSongs(Ref ref) async* {
  final rawSearchString = ref.watch(searchStringStateProvider);
  final searchFields = await ref.watch(effectiveSearchFieldsProvider.future);
  final filters = ref.watch(multiselectTagsFilterStateProvider);
  final keyFilters = ref.watch(keyFilterStateProvider);
  final bankFilters = ref.watch(banksFilterStateProvider);
  final catalog = await ref.watch(activeSongFieldCatalogProvider.future);

  final bankScope = _bankScopeClause(bankFilters);
  final filterScope = _filterClause(filters, catalog);
  final keyScope = _keyClause(keyFilters);
  final searchScope = _searchClause(rawSearchString, searchFields);
  final hasSearch = rawSearchString.trim().isNotEmpty;

  final variables = <Variable>[
    ..._ftsVariables(rawSearchString, searchFields),
    ...bankScope.variables,
    ...filterScope.variables,
    ...keyScope.variables,
    ...searchScope.variables,
  ];

  final orderBy = hasSearch
      ? '''
        ORDER BY
          CASE WHEN fts.song_id IS NULL THEN 1 ELSE 0 END,
          COALESCE(fts.rank, 0),
          songs.title COLLATE NOCASE
      '''
      : 'ORDER BY songs.title COLLATE NOCASE';

  yield* db
      .customSelect(
        '''
        SELECT
          songs.*,
          (
            SELECT GROUP_CONCAT(field_name)
            FROM assets
            WHERE assets.song_uuid = songs.uuid
          ) AS downloaded_assets,
          fts.rank AS rank,
          fts.match_title AS match_title,
          fts.match_lyrics AS match_lyrics
        FROM songs
        ${_ftsJoinSql(rawSearchString, searchFields)}
        WHERE ${bankScope.sql}
          AND ${filterScope.sql}
          AND ${keyScope.sql}
          AND ${searchScope.sql}
        $orderBy
        ''',
        variables: variables,
        readsFrom: {db.songs, db.assets},
      )
      .watch()
      .map((rows) => rows.map(_mapSongResult).toList(growable: false));
}

class SongResult {
  final Song song;
  final List<String> downloadedAssets;
  final String? matchTitle;
  final String? matchLyrics;

  SongResult(
    this.song, {
    required this.downloadedAssets,
    this.matchTitle,
    this.matchLyrics,
  });
}
