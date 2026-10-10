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

const snippetTags = (start: '<?', end: '?>');

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

@Riverpod(keepAlive: true)
Stream<List<SongResult>> filteredSongs(Ref ref) {
  final String searchString = sanitize(ref.watch(searchStringStateProvider));
  final List<String> searchFields = ref.watch(searchFieldsStateProvider);
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

  return _searchSongs(
    searchString: searchString,
    searchFields: searchFields,
    filters: filters,
    bankFilters: bankFilters,
    keyFilters: keyFilters,
  );
}

/// Searches through the app-managed FTS index (see [SongFtsIndex]). The index
/// columns, the bm25 weights and the per-column snippets are all generated
/// from the field registry, so no query here hardcodes a searchable field.
Stream<List<SongResult>> _searchSongs({
  required String searchString,
  required List<String> searchFields,
  required Map<String, List<String>> filters,
  required Set<String> bankFilters,
  required KeyFilters keyFilters,
}) {
  final index = SongFtsIndex.registry;
  final allColumns = [for (final column in index.columns) column.name];
  final selected = searchFields.where(allColumns.contains).toList();
  final matchString = selected.isEmpty || selected.length == allColumns.length
      ? searchString
      : '{${selected.join(' ')}} : $searchString';

  final variables = <Variable>[Variable<String>(matchString)];
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

  final extraWhere = clauses.isEmpty ? '' : ' AND (${clauses.join(' AND ')})';
  final sql =
      'SELECT ${index.searchColumns} '
      '${index.searchFrom} '
      'WHERE ${SongFtsIndex.tableName} MATCH ?$extraWhere '
      'ORDER BY rank';

  return db
      .customSelect(sql, variables: variables, readsFrom: {db.songs})
      .watch()
      .asyncMap((hits) async {
        if (hits.isEmpty) return const <SongResult>[];

        final ids = [for (final hit in hits) hit.read<int>('id')];
        final songRows = await (db.selectOnly(db.songs)
              ..addColumns(db.songs.$columns)
              ..addColumns([subqueryExpression(downloadedAssetsSubquery)])
              ..where(db.songs.id.isIn(ids)))
            .get();

        final songsById = {
          for (final row in songRows)
            row.read(db.songs.id): (
              song: row.readTable(db.songs),
              assets:
                  row.rawData
                      .readNullableWithType(DriftSqlType.string, 'c0')
                      ?.split(',') ??
                  const <String>[],
            ),
        };

        return [
          for (final hit in hits)
            if (songsById[hit.read<int>('id')] case final entry?)
              SongResult(
                entry.song,
                downloadedAssets: entry.assets,
                match: SongMatch(
                  rank: hit.read<double>('rank'),
                  snippets: {
                    for (final column in index.columns)
                      column.name: hit.readNullable<String>(
                        index.matchAlias(column),
                      ),
                  },
                ),
              ),
        ].where((result) => matchesKeyFilters(result.song, keyFilters)).toList();
      });
}

class SongResult {
  final Song song;
  final List<String> downloadedAssets;
  final SongMatch? match;

  SongResult(this.song, {required this.downloadedAssets, this.match});
}

/// Relevance metadata for a song matched through the search index: the bm25
/// rank and one snippet per searchable field, keyed by field name.
class SongMatch {
  final double rank;
  final Map<String, String?> snippets;

  SongMatch({required this.rank, required this.snippets});

  String? get matchTitle => snippets['title'];
  String? get matchLyrics => snippets['lyrics'];
}
