import 'package:diacritic/diacritic.dart';
import 'package:drift/drift.dart';
// ignore: experimental_member_use
import 'package:drift/extensions/json1.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/key/state.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';
import '../../data/song/song_fields.dart';
import '../bank/banks.dart';
import '../../ui/base/songs/widgets/filter/types/bank/state.dart';
import '../../ui/base/songs/widgets/filter/types/multiselect-tags/state.dart';
import '../../ui/base/songs/widgets/filter/types/search/state.dart';
import '../assets/downloaded.dart';

part 'filter.g.dart';

// far future todo: implement dynamic fts table generation based on bank data and dynamic selectable fts columns
const List<String> fullTextSearchFields = ['title', 'lyrics'];

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

  String ftsMatchString = '{${searchFields.join(' ')}} : $searchString';

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
  } else {
    return db
        .songFulltextSearch(
          (_, _) => subqueryExpression(downloadedAssetsSubquery),
          ftsMatchString,
          (_, songs) => filterExpression(songs),
        )
        .watch()
        .map(
          (results) =>
              results
                  .map(
                    (result) => SongResult(
                      result.song,
                      result: result,
                      downloadedAssets: result.assets?.split(',') ?? [],
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
}

class SongResult {
  final Song song;
  final List<String> downloadedAssets;
  final SongFulltextSearchResult? result;

  SongResult(this.song, {required this.downloadedAssets, this.result});
}
