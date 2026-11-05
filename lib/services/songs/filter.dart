import 'package:drift/drift.dart';
// ignore: experimental_member_use
import 'package:drift/extensions/json1.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/key/state.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';
import '../../data/song/song_fields.dart';
import '../../data/song/song_fts_index.dart';
import '../../ui/base/songs/widgets/filter/types/bank/state.dart';
import '../../ui/base/songs/widgets/filter/types/multiselect-tags/state.dart';
import '../../ui/base/songs/widgets/filter/types/search/state.dart';
import '../assets/downloaded.dart';
import '../bank/banks.dart';
import 'search_index.dart';

part 'filter.g.dart';

// Searchable fields come from the registry. Only title and lyrics are FTS-
// backed (song.drift); the rest match by expression over `songs`.
final List<String> fullTextSearchFields = [
  for (final field in defaultSongFieldRegistry.values)
    if (field.hasSearchUse) field.apiName,
];

/// Filterable fields at least one song has a value for, with that count.
///
/// Aggregated in SQLite, so opening the filter UI loads no songs into Dart.
@Riverpod(keepAlive: true)
Future<Map<String, ({SongField field, int count})>> existingFilterableFields(
  Ref ref,
) {
  return ref.watch(_existingFilterableFieldsStream.future);
}

/// Aggregate stream behind [existingFilterableFields].
final _existingFilterableFieldsStream =
    StreamProvider<Map<String, ({SongField field, int count})>>((ref) async* {
      final banks = await ref.watch(watchAllBanksProvider.future);
      final registry = mergeSongFields(defaultSongFieldRegistry, {
        for (final bank in banks)
          if (bank.songFields.isNotEmpty) ...bank.songFields,
      });
      yield* buildExistingFilterableFields(registry);
    });

/// Filter-card metadata for [registry]: only fields a song has a value for.
/// A text field counts non-blank values, a list field non-blank elements, and
/// the `key` pseudo-field (the `key_field` column) songs with a key.
Stream<Map<String, ({SongField field, int count})>>
buildExistingFilterableFields([Map<String, SongField>? registry]) {
  final effectiveRegistry = registry ?? defaultSongFieldRegistry;
  final query = _existingFilterableFieldsQuery(effectiveRegistry);
  if (query == null) {
    return Stream.value(const <String, ({SongField field, int count})>{});
  }
  return db
      .customSelect(
        query.sql,
        variables: query.variables,
        readsFrom: {db.songs},
      )
      .watch()
      .map((rows) => _readExistingFilterableFields(rows, effectiveRegistry));
}

/// The aggregate query behind [buildExistingFilterableFields].
///
/// `json_each(content_map)` gives one row per field, so `COUNT(DISTINCT id)`
/// counts songs. `json('[]')` keeps the nested array expansion valid for
/// scalar rows; `key_field` is unioned in for the `key` pseudo-field.
({String sql, List<Variable> variables})? _existingFilterableFieldsQuery(
  Map<String, SongField> registry,
) {
  final contentFields = [
    for (final field in registry.values)
      if (field.hasFilterUse && field.apiName != 'key') field.apiName,
  ];

  final selects = <String>[];
  final variables = <Variable>[];

  if (contentFields.isNotEmpty) {
    final placeholders = List.filled(contentFields.length, '?').join(', ');
    variables.addAll(contentFields.map(Variable<String>.new));
    selects.add('''
      SELECT entry.key AS field, COUNT(DISTINCT songs.id) AS song_count
      FROM songs, json_each(songs.content_map) AS entry
      WHERE entry.key IN ($placeholders)
        AND (
          (entry.type = 'array' AND EXISTS (
            SELECT 1
            FROM json_each(
              CASE WHEN entry.type = 'array' THEN entry.value ELSE json('[]') END
            ) AS element
            WHERE TRIM(CAST(element.value AS TEXT)) <> ''
          ))
          OR (entry.type <> 'array' AND TRIM(CAST(entry.value AS TEXT)) <> '')
        )
      GROUP BY entry.key
    ''');
  }

  if (registry['key'] != null) {
    selects.add('''
      SELECT 'key' AS field, COUNT(*) AS song_count
      FROM songs
      WHERE TRIM(COALESCE(key_field, '')) <> ''
      HAVING COUNT(*) > 0
    ''');
  }

  if (selects.isEmpty) return null;
  return (sql: selects.join('\nUNION ALL\n'), variables: variables);
}

Map<String, ({SongField field, int count})> _readExistingFilterableFields(
  List<QueryRow> rows,
  Map<String, SongField> registry,
) {
  final fields = <String, ({SongField field, int count})>{};
  for (final row in rows) {
    final name = row.read<String>('field');
    final field = registry[name];
    if (field == null || !field.hasFilterUse) continue;
    fields[name] = (field: field, count: row.read<int>('song_count'));
  }
  return fields;
}

/// Number of songs in the collection - the "total" in the filters subtitle.
@Riverpod(keepAlive: true)
Stream<int> songTotalCount(Ref ref) {
  return db
      .customSelect('SELECT COUNT(*) AS count FROM songs')
      .watch()
      .map((rows) => rows.first.read<int>('count'));
}

/// Matching songs - the "filtered" count in the filters subtitle, taken from
/// the list query's window count ([SongResultPage.total]).
@Riverpod(keepAlive: true)
int? songMatchCount(Ref ref) {
  return ref.watch(filteredSongsProvider).value?.total;
}

const snippetTags = (
  start: SongFtsIndex.snippetStart,
  end: SongFtsIndex.snippetEnd,
);

/// The empty key filter, for callers that must not apply one.
const noKeyFilters = (
  pitches: <String>{},
  modes: <String>{},
  keys: <KeyField>{},
);

bool matchesKeyFilters(Song song, KeyFilters keyFilters) =>
    matchesKeyField(song.keyField, keyFilters);

/// [matchesKeyFilters] for callers holding only the raw key field.
bool matchesKeyField(List<KeyField> keyField, KeyFilters keyFilters) {
  if (keyFilters.isEmpty) return true;

  final matchesCompleteKey =
      keyFilters.keys.isNotEmpty &&
      keyField.any((key) => keyFilters.keys.contains(key));

  final matchesPitchGroup =
      keyFilters.pitches.isEmpty ||
      keyField.any((key) => keyFilters.pitches.contains(key.pitch));

  final matchesModeGroup =
      keyFilters.modes.isEmpty ||
      keyField.any((key) => keyFilters.modes.contains(key.mode));

  final matchesPartialKeyGroup =
      (keyFilters.pitches.isNotEmpty || keyFilters.modes.isNotEmpty) &&
      matchesPitchGroup &&
      matchesModeGroup;

  return matchesCompleteKey || matchesPartialKeyGroup;
}

/// Results per page; [SongResultsLimit] grows it as the list is scrolled.
const songSearchPageSize = 50;

/// How many results are requested. Its own notifier (not a family keyed by the
/// limit) so growing it recomputes [filteredSongs] in place: loaded results
/// stay on screen and the page shows a footer spinner.
@riverpod
class SongResultsLimit extends _$SongResultsLimit {
  @override
  int build() {
    // A new query starts from the first page.
    ref.listen(searchStringStateProvider, (previous, next) {
      if (previous != next) reset();
    });
    return songSearchPageSize;
  }

  void loadMore() => state += songSearchPageSize;

  void reset() => state = songSearchPageSize;
}

@Riverpod(keepAlive: true)
Stream<SongResultPage> filteredSongs(Ref ref) {
  return songResults(
    searchString: sanitize(ref.watch(searchStringStateProvider)),
    searchFields: ref.watch(searchFieldsStateProvider),
    filters: ref.watch(multiselectTagsFilterStateProvider),
    bankFilters: ref.watch(banksFilterStateProvider),
    keyFilters: ref.watch(keyFilterStateProvider),
    limit: ref.watch(songResultsLimitProvider),
  );
}

/// The paginated query behind the songs page: folded-title order without a
/// term, [searchSongs] relevance with one. Both apply the same filters and
/// report the full match count.
Stream<SongResultPage> songResults({
  required String searchString,
  required List<String> searchFields,
  required Map<String, List<String>> filters,
  required Set<String> bankFilters,
  required KeyFilters keyFilters,
  required int limit,
}) {
  if (searchString.isEmpty) {
    return filteredSongsPage(
      filters: filters,
      bankFilters: bankFilters,
      keyFilters: keyFilters,
      limit: limit,
    );
  }
  return searchSongs(
    searchString: searchString,
    searchFields: searchFields,
    filters: filters,
    bankFilters: bankFilters,
    keyFilters: keyFilters,
    limit: limit,
  );
}

/// `songs.title` folded for a diacritic-insensitive order
/// ([SongFtsIndex.foldExpression]).
final String foldedTitle = SongFtsIndex.foldExpression('songs.title');

/// The plain listing: songs matching the filters, folded-title order, paged
/// with [limit]. The window count rides along.
Stream<SongResultPage> filteredSongsPage({
  required Map<String, List<String>> filters,
  required Set<String> bankFilters,
  required KeyFilters keyFilters,
  required int limit,
}) {
  return (db.select(db.songs).addColumns([
          subqueryExpression(downloadedAssetsSubquery),
          // `COUNT(*) OVER ()` counts rows before LIMIT; drift aliases the
          // added expressions `c0`, `c1`, ...
          CustomExpression<int>('COUNT(*) OVER ()'),
        ])
        ..where(filterExpression(db.songs, filters, bankFilters, keyFilters))
        ..orderBy([
          OrderingTerm.asc(CustomExpression<String>(foldedTitle)),
          OrderingTerm.asc(db.songs.id),
        ])
        ..limit(limit))
      .watch()
      .map(
        (rows) => SongResultPage([
          for (final row in rows)
            SongResult(
              row.readTable(db.songs),
              downloadedAssets:
                  row.rawData
                      .readNullableWithType(DriftSqlType.string, 'c0')
                      ?.split(',') ??
                  const <String>[],
            ),
        ], _windowTotal(rows)),
      );
}

int _windowTotal(List<TypedResult> rows) {
  if (rows.isEmpty) return 0;
  return rows.first.rawData.readNullableWithType(DriftSqlType.int, 'c1') ?? 0;
}

/// Tag, bank and key filters as a drift expression ([filteredSongsPage]).
Expression<bool> filterExpression(
  Songs songs,
  Map<String, List<String>> filters,
  Set<String> bankFilters,
  KeyFilters keyFilters,
) {
  return Expression.and(
    filters.entries
        .map((entry) {
          final fieldData = songs.contentMap.jsonExtract<String>(
            '\$.${entry.key}',
          );
          // List fields match the quoted element (json_extract keeps array
          // elements quoted), text fields plainly.
          return Expression.or(
            entry.value.map((value) {
              final likePattern = bankApiListValueFields.contains(entry.key)
                  ? '%"$value"%'
                  : '%$value%';
              return fieldData.like(likePattern);
            }),
          );
        })
        .followedBy([
          if (bankFilters.isNotEmpty)
            Expression.or(bankFilters.map((b) => songs.sourceBank.equals(b))),
          keyFilterExpression(songs, keyFilters),
        ]),
  );
}

/// SQL mirror of [matchesKeyFilters]: `key_field` holds `pitch-mode` key
/// strings joined with ', ' - a key is a substring, a pitch anchors on the
/// trailing dash, a mode on the leading one.
Expression<bool> keyFilterExpression(Songs songs, KeyFilters keyFilters) {
  if (keyFilters.isEmpty) return const Constant(true);

  final parts = <Expression<bool>>[];
  if (keyFilters.keys.isNotEmpty) {
    parts.add(
      Expression.or(
        keyFilters.keys.map((key) => songs.keyField.like('%$key%')),
      ),
    );
  }
  if (keyFilters.pitches.isNotEmpty || keyFilters.modes.isNotEmpty) {
    final pitch = keyFilters.pitches.isEmpty
        ? const Constant(true)
        : Expression.or(
            keyFilters.pitches.map((pitch) => songs.keyField.like('%$pitch-%')),
          );
    final mode = keyFilters.modes.isEmpty
        ? const Constant(true)
        : Expression.or(
            keyFilters.modes.map((mode) => songs.keyField.like('%-$mode%')),
          );
    parts.add(pitch & mode);
  }
  return Expression.or(parts);
}

/// The selected [searchFields], or all of them when none is selected.
List<String> searchableFields(List<String> searchFields) {
  final selected = searchFields.toSet();
  final fields = [
    for (final field in fullTextSearchFields)
      if (selected.isEmpty || selected.contains(field)) field,
  ];
  assert(
    fields.isNotEmpty,
    'search fields must intersect the searchable fields',
  );
  return fields;
}

/// SQL `WHERE` for the tag, bank and key filters, shared with the search so
/// both see the same rows.
({String where, List<Variable> variables}) filterWhere(
  Map<String, List<String>> filters,
  Set<String> bankFilters,
  KeyFilters keyFilters,
) {
  final variables = <Variable>[];
  final clauses = <String>[];

  for (final entry in filters.entries) {
    final valueClauses = <String>[];
    for (final value in entry.value) {
      // Quoted matching for list fields, plain for text - mirrors
      // [filterExpression].
      final likePattern = bankApiListValueFields.contains(entry.key)
          ? '%"$value"%'
          : '%$value%';
      valueClauses.add(
        "json_extract(songs.content_map, '\$.${entry.key}') LIKE ?",
      );
      variables.add(Variable<String>(likePattern));
    }
    if (valueClauses.isNotEmpty) clauses.add('(${valueClauses.join(' OR ')})');
  }
  if (bankFilters.isNotEmpty) {
    clauses.add(
      '(${bankFilters.map((_) => 'songs.source_bank = ?').join(' OR ')})',
    );
    variables.addAll(bankFilters.map(Variable<String>.new));
  }
  if (keyFilters.isNotEmpty) {
    // Mirrors [keyFilterExpression]: keys are substrings, a pitch anchors on
    // the trailing dash, a mode on the leading one.
    final keyClauses = <String>[];
    if (keyFilters.keys.isNotEmpty) {
      keyClauses.add(
        '(${keyFilters.keys.map((_) => 'songs.key_field LIKE ?').join(' OR ')})',
      );
      variables.addAll(
        keyFilters.keys.map((key) => Variable<String>('%$key%')),
      );
    }
    if (keyFilters.pitches.isNotEmpty || keyFilters.modes.isNotEmpty) {
      final pitch = keyFilters.pitches.isEmpty
          ? '1'
          : '(${keyFilters.pitches.map((_) => 'songs.key_field LIKE ?').join(' OR ')})';
      variables.addAll(
        keyFilters.pitches.map((pitch) => Variable<String>('%$pitch-%')),
      );
      final mode = keyFilters.modes.isEmpty
          ? '1'
          : '(${keyFilters.modes.map((_) => 'songs.key_field LIKE ?').join(' OR ')})';
      variables.addAll(
        keyFilters.modes.map((mode) => Variable<String>('%-$mode%')),
      );
      keyClauses.add('($pitch AND $mode)');
    }
    clauses.add('(${keyClauses.join(' OR ')})');
  }

  return (where: clauses.join(' AND '), variables: variables);
}

/// Searches the drift-owned FTS index ([SongFtsIndex]): FTS5 for title/lyrics,
/// folded LIKE and exact equality for the rest.
///
/// Two phases - a custom select for the hits and the window total, then a typed
/// select for the songs, which `readTable` needs.
Stream<SongResultPage> searchSongs({
  required String searchString,
  required List<String> searchFields,
  required Map<String, List<String>> filters,
  required Set<String> bankFilters,
  required KeyFilters keyFilters,
  required int limit,
}) {
  final fields = searchableFields(searchFields);
  final extra = filterWhere(filters, bankFilters, keyFilters);

  final query = SongFtsIndex.buildSearchQuery(
    term: searchString,
    fields: fields,
    limit: limit,
    extraWhere: extra.where,
    extraVariables: extra.variables,
  );

  final foldedTerm = SongFtsIndex.foldTerm(searchString);

  // The query that reads the FTS content, so the one that trips over a corrupt
  // index; it heals itself ([withSearchIndexRepair]).
  return withSearchIndexRepair(
    () => db
        .customSelect(
          query.sql,
          variables: query.variables,
          readsFrom: {db.songs},
        )
        .watch()
        .asyncMap((hits) async {
          if (hits.isEmpty) return const SongResultPage([], 0);

          final total = hits.first.read<int>('total');
          final uuids = [for (final hit in hits) hit.read<String>('uuid')];
          final rows = await (db.select(db.songs).addColumns([
            subqueryExpression(downloadedAssetsSubquery),
          ])..where(db.songs.uuid.isIn(uuids))).get();
          final songsByUuid = {
            for (final row in rows) row.readTable(db.songs).uuid: row,
          };

          return SongResultPage([
            for (final hit in hits)
              if (songsByUuid[hit.read<String>('uuid')] case final row?)
                SongResult(
                  row.readTable(db.songs),
                  downloadedAssets:
                      row.rawData
                          .readNullableWithType(DriftSqlType.string, 'c0')
                          ?.split(',') ??
                      const <String>[],
                  match: SongMatch(
                    tier: hit.read<int>('tier'),
                    rank: hit.readNullable<double>('rank') ?? 0,
                    matches: _matchedFields(
                      row.readTable(db.songs),
                      hit,
                      fields,
                      foldedTerm,
                    ),
                  ),
                ),
          ], total);
        }),
  );
}

/// Snippets for the fields a song matched in, by field name. The FTS snippet is
/// preferred; hits the trigram index cannot cover (short terms, exact matches)
/// get one built in Dart around the folded match.
Map<String, String> _matchedFields(
  Song song,
  QueryRow hit,
  List<String> fields,
  String foldedTerm,
) {
  final matched = <String, String>{};
  for (final field in fields) {
    // Only FTS-backed fields have a snippet column.
    final ftsSnippet = SongFtsIndex.isFtsField(field)
        ? hit.readNullable<String>(SongFtsIndex.matchAlias(field))
        : null;
    if (ftsSnippet != null && ftsSnippet.contains(SongFtsIndex.snippetStart)) {
      matched[field] = ftsSnippet;
      continue;
    }
    final value = _fieldValue(song, field);
    if (value == null) continue;
    final snippet = _snippetFor(value, foldedTerm);
    if (snippet != null) matched[field] = snippet;
  }
  return matched;
}

String? _fieldValue(Song song, String field) => switch (field) {
  'title' => song.title,
  'lyrics' => song.lyrics,
  _ => song.contentDisplay(field),
};

/// Slices [value] around its folded match of [foldedTerm], wrapped in the
/// snippet tags. The fold maps characters one-to-one, so indices line up.
String? _snippetFor(String value, String foldedTerm) {
  if (foldedTerm.isEmpty) return null;
  final index = SongFtsIndex.foldTerm(value).indexOf(foldedTerm);
  if (index < 0) return null;

  const context = 20;
  final start = index - context < 0 ? 0 : index - context;
  final matchEnd = index + foldedTerm.length;
  final end = matchEnd + context > value.length
      ? value.length
      : matchEnd + context;

  return '${start > 0 ? '...' : ''}${value.substring(start, index)}'
      '${SongFtsIndex.snippetStart}${value.substring(index, matchEnd)}'
      '${SongFtsIndex.snippetEnd}${value.substring(matchEnd, end)}'
      '${end < value.length ? '...' : ''}';
}

class SongResult {
  final Song song;
  final List<String> downloadedAssets;
  final SongMatch? match;

  SongResult(this.song, {required this.downloadedAssets, this.match});
}

/// Match metadata: tier (0 exact, 1 substring, 2 FTS-only), bm25 rank and
/// snippets by field.
class SongMatch {
  final int tier;
  final double rank;
  final Map<String, String> matches;

  SongMatch({required this.tier, required this.rank, required this.matches});

  String? get matchTitle => matches['title'];
  String? get matchLyrics => matches['lyrics'];
}

/// One page of the songs list plus [total] - the window count from the same
/// statement, before the limit.
class SongResultPage {
  final List<SongResult> results;
  final int total;

  const SongResultPage(this.results, this.total);
}
