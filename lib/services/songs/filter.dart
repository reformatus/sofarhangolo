import 'package:diacritic/diacritic.dart';
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

// Searchable fields come from the registry-driven index layout; the selector
// UI lists them uniformly.
final List<String> fullTextSearchFields = [
  for (final column in SongFtsIndex.registry.columns) column.name,
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

const snippetTags = (
  start: SongFtsIndex.snippetStart,
  end: SongFtsIndex.snippetEnd,
);

bool matchesKeyFilters(Song song, KeyFilters keyFilters) {
  if (keyFilters.isEmpty) return true;

  final matchesCompleteKey =
      keyFilters.keys.isNotEmpty &&
      song.keyField.any((key) => keyFilters.keys.contains(key));

  final matchesPitchGroup =
      keyFilters.pitches.isEmpty ||
      song.keyField.any((key) => keyFilters.pitches.contains(key.pitch));

  final matchesModeGroup =
      keyFilters.modes.isEmpty ||
      song.keyField.any((key) => keyFilters.modes.contains(key.mode));

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
  final String searchString = sanitize(ref.watch(searchStringStateProvider));
  final List<String> searchFields = ref.watch(searchFieldsStateProvider);
  final int limit = ref.watch(songResultsLimitProvider);
  final Map<String, List<String>> filters = ref.watch(
    multiselectTagsFilterStateProvider,
  );
  final KeyFilters keyFilters = ref.watch(keyFilterStateProvider);
  final Set<String> bankFilters = ref.watch(banksFilterStateProvider);

  Expression<bool> filterExpression(Songs songs) {
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
          ]),
    );
  }

  if (searchString.isEmpty) {
    return ((db.select(db.songs).addColumns([
                subqueryExpression(downloadedAssetsSubquery),
              ])
              // Sort afterwards to handle diacritics
              // ..orderBy([OrderingTerm.asc(db.songs.title)])
              ..where(filterExpression(db.songs)))
            .watch())
        .map(
          (resultList) =>
              resultList
                  .map(
                    (result) => SongResult(
                      result.readTable(db.songs),
                      downloadedAssets:
                          (result.rawData.readNullableWithType(
                            DriftSqlType.string,
                            'c0',
                          ))?.split(',') ??
                          [],
                    ),
                  )
                  .where((result) => matchesKeyFilters(result.song, keyFilters))
                  .toList()
                ..sort(
                  (a, b) =>
                      removeDiacritics(a.song.title)
                          .compareTo(removeDiacritics(b.song.title)),
                ),
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

/// Searches through the app-managed FTS index (see [SongFtsIndex]). The index
/// columns, the bm25 weights and the per-column snippets are all generated
/// from the field registry, so no query here hardcodes a searchable field.
///
/// Two phases: a custom select reads the dynamic hit columns (uuid, rank and
/// snippets) in rank order, then a normal typed select resolves those songs.
/// A single query cannot be typed: `readTable` needs drift-generated table
/// metadata, which the registry-dynamic index deliberately does not have.
Stream<List<SongResult>> searchSongs({
  required String searchString,
  required List<String> searchFields,
  required Map<String, List<String>> filters,
  required Set<String> bankFilters,
  required KeyFilters keyFilters,
  required int limit,
}) {
  final index = SongFtsIndex.registry;
  final allColumns = [for (final column in index.columns) column.name];
  final selected = searchFields.where(allColumns.contains).toSet();
  final fields = selected.isEmpty
      ? index.columns
      : [
          for (final column in index.columns)
            if (selected.contains(column.name)) column,
        ];
  assert(fields.isNotEmpty, 'search fields must intersect the index columns');

  final variables = <Variable>[];
  final clauses = <String>[];

  for (final entry in filters.entries) {
    final valueClauses = <String>[];
    for (final value in entry.value) {
      // Quoted matching for list fields, plain for text fields — mirrors the
      // drift expression filter above.
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
    clauses.add('(${bankFilters.map((_) => 'songs.source_bank = ?').join(' OR ')})');
    variables.addAll(bankFilters.map(Variable<String>.new));
  }

  final query = index.buildSearchQuery(
    term: searchString,
    fields: fields,
    limit: limit,
    extraWhere: clauses.join(' AND '),
    extraVariables: variables,
  );

  final foldedTerm = SongFtsIndex.foldTerm(searchString);

  return db
      .customSelect(query.sql, variables: query.variables, readsFrom: {db.songs})
      .watch()
      .asyncMap((hits) async {
        if (hits.isEmpty) return const <SongResult>[];

        final uuids = [for (final hit in hits) hit.read<String>('uuid')];
        final rows =
            await (db.select(db.songs)
                  .addColumns([subqueryExpression(downloadedAssetsSubquery)])
                  ..where(db.songs.uuid.isIn(uuids)))
                .get();
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
                    index,
                    foldedTerm,
                  ),
                ),
              ),
        ].where((result) => matchesKeyFilters(result.song, keyFilters)).toList();
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
  SongFtsIndex index,
  String foldedTerm,
) {
  final matched = <String, String>{};
  for (final column in index.columns) {
    final ftsSnippet = hit.readNullable<String>(index.matchAlias(column));
    if (ftsSnippet != null && ftsSnippet.contains(SongFtsIndex.snippetStart)) {
      matched[column.name] = ftsSnippet;
      continue;
    }
    final value = _fieldValue(song, column.name);
    if (value == null) continue;
    final snippet = _snippetFor(value, foldedTerm);
    if (snippet != null) matched[column.name] = snippet;
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
  final end = matchEnd + context > value.length ? value.length : matchEnd + context;

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
