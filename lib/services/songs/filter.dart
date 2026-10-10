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
import '../bank/banks.dart';
import '../../ui/base/songs/widgets/filter/types/bank/state.dart';
import '../../ui/base/songs/widgets/filter/types/multiselect-tags/state.dart';
import '../../ui/base/songs/widgets/filter/types/search/state.dart';
import '../assets/downloaded.dart';

part 'filter.g.dart';

// Searchable fields come from the field registry; the selector UI lists them
// uniformly. Only title and lyrics are backed by the FTS index (song.drift) -
// the rest are matched by expression over `songs` (see [SongFtsIndex]).
final List<String> fullTextSearchFields = [
  for (final field in defaultSongFieldRegistry.values)
    if (field.hasSearchUse) field.apiName,
];

/// Filterable fields that at least one song carries a value for, with the
/// number of such songs.
///
/// The counts are aggregated in SQLite (`json_each` over `content_map` plus
/// the dedicated `key` column), so opening the filter UI never has to load
/// every song into Dart.
@Riverpod(keepAlive: true)
Future<Map<String, ({SongField field, int count})>> existingFilterableFields(
  Ref ref,
) {
  return ref.watch(_existingFilterableFieldsStream.future);
}

/// Aggregate stream behind [existingFilterableFields], recomputed whenever the
/// bank overlays or the `songs` table change.
final _existingFilterableFieldsStream =
    StreamProvider<Map<String, ({SongField field, int count})>>((ref) async* {
      final banks = await ref.watch(watchAllBanksProvider.future);
      final registry = mergeSongFields(defaultSongFieldRegistry, {
        for (final bank in banks)
          if (bank.songFields.isNotEmpty) ...bank.songFields,
      });
      yield* buildExistingFilterableFields(registry);
    });

/// Reactive stream of the filter-card metadata for [registry].
///
/// Only fields at least one song has are returned: registry fields without a
/// filter use are skipped, a text field counts songs with a non-blank value, a
/// list field counts songs with at least one non-blank element, and the
/// pseudo-field `key` (backed by the `key_field` column, not `content_map`)
/// counts songs with a key.
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

/// The single aggregate query behind [buildExistingFilterableFields].
///
/// `json_each(content_map)` yields one row per field a song stores, so
/// `COUNT(DISTINCT songs.id)` counts songs rather than values. Array values
/// are expanded through a nested `json_each` to require at least one non-blank
/// element; `json('[]')` keeps that nested call valid for scalar rows. The
/// `key` pseudo-field comes from `key_field` and is unioned in.
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

/// Sorted distinct non-blank values of a filter field across every song.
///
/// List fields contribute each element; both scalar and element values are
/// trimmed, so the chip values line up with what the filters match.
@Riverpod(keepAlive: true)
Future<List<String>> selectableValuesForFilterableField(Ref ref, String field) {
  return ref.watch(_selectableValuesStream(field).future);
}

final _selectableValuesStream = StreamProvider.family<List<String>, String>(
  (ref, field) => _watchSelectableValues(field),
);

Stream<List<String>> _watchSelectableValues(String field) {
  // Two branches because scalar values are plain text (not valid JSON, so
  // `json_each` would reject them) while list values are JSON arrays.
  const sql = '''
    SELECT DISTINCT value FROM (
      SELECT TRIM(CAST(element.value AS TEXT)) AS value
      FROM songs, json_each(songs.content_map) AS entry,
           json_each(
             CASE WHEN entry.type = 'array' THEN entry.value ELSE json('[]') END
           ) AS element
      WHERE entry.key = ?
      UNION
      SELECT TRIM(CAST(entry.value AS TEXT)) AS value
      FROM songs, json_each(songs.content_map) AS entry
      WHERE entry.key = ? AND entry.type <> 'array'
    )
    WHERE value <> ''
    ORDER BY value
  ''';

  return db
      .customSelect(
        sql,
        variables: [Variable<String>(field), Variable<String>(field)],
        readsFrom: {db.songs},
      )
      .watch()
      .map((rows) => [for (final row in rows) row.read<String>('value')]);
}

/// Number of songs in the collection - the "total" in the filters subtitle.
@Riverpod(keepAlive: true)
Stream<int> songTotalCount(Ref ref) {
  return db
      .customSelect('SELECT COUNT(*) AS count FROM songs')
      .watch()
      .map((rows) => rows.first.read<int>('count'));
}

/// Number of songs matching the current search and filters - the "filtered"
/// count in the filters subtitle.
///
/// Taken from the list query's own window count ([SongResultPage.total]), so
/// the subtitle costs no second query.
@Riverpod(keepAlive: true)
int? songMatchCount(Ref ref) {
  return ref.watch(filteredSongsProvider).value?.total;
}

const snippetTags = (
  start: SongFtsIndex.snippetStart,
  end: SongFtsIndex.snippetEnd,
);

bool matchesKeyFilters(Song song, KeyFilters keyFilters) =>
    matchesKeyField(song.keyField, keyFilters);

/// Whether a song's key fields satisfy the key filter, mirroring
/// [matchesKeyFilters] for callers that only have the raw key field.
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

/// Number of results fetched per page; [SongResultsLimit] grows it as the
/// results list is scrolled to the end.
const songSearchPageSize = 50;

/// How many search results are currently requested. Kept as its own notifier
/// (rather than a provider family keyed by the limit) so that growing it
/// recomputes [filteredSongs] in place: the list keeps showing the already
/// loaded results while the next page is fetched, and the page can render a
/// footer spinner instead of swapping the whole view for one.
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

/// The one paginated query behind the songs page.
///
/// [limit] always applies - with or without a search term - so the page grows
/// its window by the same rule in both cases (see [SongResultsLimit]). Without
/// a term the songs are ordered by folded title; with one, by the relevance
/// order of [searchSongs]. Both apply the same tag, bank and key filters, and
/// both report the full match count alongside the page.
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

/// `songs.title` folded for a diacritic-insensitive order - the SQL equivalent
/// of the Dart `removeDiacritics(...).compareTo(...)` sort it replaces (see
/// [SongFtsIndex.foldExpression]).
final String foldedTitle = SongFtsIndex.foldExpression('songs.title');

/// The plain listing: songs matching the filters only, ordered by folded title
/// and paged with [limit].
/// The plain listing: songs matching the filters only, ordered by folded title
/// and paged with [limit]. The window count rides along, so the total comes
/// from the same query.
Stream<SongResultPage> filteredSongsPage({
  required Map<String, List<String>> filters,
  required Set<String> bankFilters,
  required KeyFilters keyFilters,
  required int limit,
}) {
  return (db.select(db.songs).addColumns([
          subqueryExpression(downloadedAssetsSubquery),
          // `COUNT(*) OVER ()` counts the rows matching the WHERE, before the
          // LIMIT; drift aliases added expressions `c0`, `c1`, ...
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

/// Drift expression for the tag and bank filters plus the key filter, used by
/// the plain listing ([filteredSongsPage]).
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
          // json_extract unquotes scalars but keeps array elements
          // quoted, so list fields match on the quoted element (avoids
          // substring hits inside longer values) while text fields match
          // plainly.
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

/// SQL mirror of [matchesKeyFilters]: `key_field` stores a song's keys as
/// `pitch-mode` joined with ', '. A complete key is a plain substring, a pitch
/// anchors on the trailing dash and a mode on the leading one. Pitch and mode
/// may be satisfied by different keys, exactly as [matchesKeyFilters] allows.
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

/// The searchable field names selected by [searchFields]; all of them when the
/// selection is empty, and the known subset otherwise.
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

/// SQL `WHERE` for the tag, bank and key filters, shared by the search query
/// and the match count so both see the same rows.
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
      // Quoted matching for list fields, plain for text fields — mirrors the
      // drift expression filter used without a search.
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
    // Mirrors [matchesKeyFilters] / [keyFilterExpression]: complete keys are
    // plain substrings, a pitch anchors on the trailing dash, a mode on the
    // leading one, and pitch/mode may come from different keys.
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

/// Searches the drift-owned FTS index (see [SongFtsIndex]): `title` and
/// `lyrics` are matched by FTS5, every other searchable field by a folded LIKE
/// or exact equality over `songs`, so the index layout stays static.
///
/// Two phases: a custom select reads the hit columns (uuid, rank, tier and
/// snippets) plus the window total, then a normal typed select resolves those
/// songs. A single query cannot be typed: the FTS columns drift cannot join
/// into `readTable`.
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

  return db
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
      });
}

/// Highlighted snippets for the fields a song matched in, keyed by field name.
///
/// The FTS snippet is preferred (it is index-driven, token-based); for hits
/// the trigram index cannot cover — short terms, and exact/substring matches
/// outside the FTS' reach — a snippet is built in Dart around the folded
/// match, so LIKE and exact hits highlight just like FTS ones.
Map<String, String> _matchedFields(
  Song song,
  QueryRow hit,
  List<String> fields,
  String foldedTerm,
) {
  final matched = <String, String>{};
  for (final field in fields) {
    // Only the FTS-backed fields have a snippet column; the rest fall back to
    // a Dart snippet around the folded match.
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

/// Slices [value] around its folded match of [foldedTerm] and wraps the match
/// in the snippet highlight tags. The fold maps characters one-to-one, so
/// indices in the folded string line up with the original.
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

/// Relevance metadata for a song matched through the search index: the match
/// tier (0 exact, 1 substring, 2 FTS-only), the bm25 rank, and highlighted
/// snippets for the fields that matched, keyed by field name.
class SongMatch {
  final int tier;
  final double rank;
  final Map<String, String> matches;

  SongMatch({required this.tier, required this.rank, required this.matches});

  String? get matchTitle => matches['title'];
  String? get matchLyrics => matches['lyrics'];
}

/// One page of the songs list plus [total], the number of rows the query
/// matched before its limit. The count is a window count in the same statement,
/// so the page and the subtitle never disagree and never need a second query.
class SongResultPage {
  final List<SongResult> results;
  final int total;

  const SongResultPage(this.results, this.total);
}
