import 'package:drift/drift.dart';
// ignore: experimental_member_use
import 'package:drift/extensions/json1.dart';
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

// todo write test
@Riverpod(keepAlive: true)
Future<Map<String, ({SongField field, int count})>> existingFilterableFields(
  Ref ref,
) async {
  final banks = await ref.watch(watchAllBanksProvider.future);
  final registry = mergeSongFields(defaultSongFieldRegistry, {
    for (final bank in banks)
      if (bank.songFields.isNotEmpty) ...bank.songFields,
  });
  return buildExistingFilterableFields(
    await ref.watch(allSongsProvider.future),
    registry,
  );
}

Map<String, ({SongField field, int count})> buildExistingFilterableFields(
  Iterable<Song> songs, [
  Map<String, SongField>? registry,
]) {
  final effectiveRegistry = registry ?? defaultSongFieldRegistry;
  Map<String, ({SongField field, int count})> fields = {};

  for (var song in songs) {
    if (song.keyField.isNotEmpty) {
      final keyDef = effectiveRegistry['key']!;
      final existing = fields['key'];
      fields['key'] = (field: keyDef, count: (existing?.count ?? 0) + 1);
    }

    for (var field in song.contentMap.keys) {
      final fieldDef = effectiveRegistry[field];
      if (fieldDef == null || !fieldDef.hasFilterUse) continue;
      if (!song.hasContent(field)) continue;
      final existing = fields[field];
      fields[field] = (field: fieldDef, count: (existing?.count ?? 0) + 1);
    }
  }

  return fields;
}

@Riverpod(keepAlive: true)
Future<List<String>> selectableValuesForFilterableField(
  Ref ref,
  String field,
) async {
  final allSongs = Stream.fromIterable(
    await ref.watch(allSongsProvider.future),
  );
  Set<String> values = {};

  await for (Song song in allSongs) {
    values.addAll(song.contentList(field));
  }

  values.remove("");
  final list = values.toList();
  list.sort();
  return list;
}

@Riverpod(keepAlive: true)
Stream<List<Song>> allSongs(Ref ref) {
  return db.select(db.songs).watch();
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
/// count in the filters subtitle (see [countSongs]).
@Riverpod(keepAlive: true)
Stream<int> songMatchCount(Ref ref) {
  return countSongs(
    searchString: sanitize(ref.watch(searchStringStateProvider)),
    searchFields: ref.watch(searchFieldsStateProvider),
    filters: ref.watch(multiselectTagsFilterStateProvider),
    bankFilters: ref.watch(banksFilterStateProvider),
    keyFilters: ref.watch(keyFilterStateProvider),
  );
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
Stream<List<SongResult>> filteredSongs(Ref ref) {
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
/// order of [searchSongs]. Both apply the same tag, bank and key filters.
Stream<List<SongResult>> songResults({
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
Stream<List<SongResult>> filteredSongsPage({
  required Map<String, List<String>> filters,
  required Set<String> bankFilters,
  required KeyFilters keyFilters,
  required int limit,
}) {
  return (db.select(db.songs).addColumns([
          subqueryExpression(downloadedAssetsSubquery),
        ])
        ..where(filterExpression(db.songs, filters, bankFilters, keyFilters))
        ..orderBy([
          OrderingTerm.asc(CustomExpression<String>(foldedTitle)),
          OrderingTerm.asc(db.songs.id),
        ])
        ..limit(limit))
      .watch()
      .map(
        (rows) => [
          for (final row in rows)
            SongResult(
              row.readTable(db.songs),
              downloadedAssets:
                  row.rawData
                      .readNullableWithType(DriftSqlType.string, 'c0')
                      ?.split(',') ??
                  const <String>[],
            ),
        ],
      );
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

/// Total number of songs matching the current search and filters.
///
/// Uses the same [filterWhere] predicates as the page query, so the count
/// agrees with the results even though those are paginated.
Stream<int> countSongs({
  required String searchString,
  required List<String> searchFields,
  required Map<String, List<String>> filters,
  required Set<String> bankFilters,
  required KeyFilters keyFilters,
}) {
  final extra = filterWhere(filters, bankFilters, keyFilters);
  final query = SongFtsIndex.countQuery(
    term: searchString.isEmpty ? null : searchString,
    fields: searchableFields(searchFields),
    extraWhere: extra.where,
    extraVariables: extra.variables,
  );

  return db
      .customSelect(
        query.sql,
        variables: query.variables,
        readsFrom: {db.songs},
      )
      .watch()
      .map((rows) => rows.first.read<int>('count'));
}

/// Searches the drift-owned FTS index (see [SongFtsIndex]): `title` and
/// `lyrics` are matched by FTS5, every other searchable field by a folded LIKE
/// or exact equality over `songs`, so the index layout stays static.
///
/// Two phases: a custom select reads the hit columns (uuid, rank, tier and
/// snippets), then a normal typed select resolves those songs. A single query
/// cannot be typed: the FTS columns drift cannot join into `readTable`.
Stream<List<SongResult>> searchSongs({
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
        if (hits.isEmpty) return const <SongResult>[];

        final uuids = [for (final hit in hits) hit.read<String>('uuid')];
        final rows = await (db.select(db.songs).addColumns([
          subqueryExpression(downloadedAssetsSubquery),
        ])..where(db.songs.uuid.isIn(uuids))).get();
        final songsByUuid = {
          for (final row in rows) row.readTable(db.songs).uuid: row,
        };

        return [
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
        ];
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
