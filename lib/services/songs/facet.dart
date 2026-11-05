import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';
import '../../data/song/song_fts_index.dart';
import '../../ui/base/songs/widgets/filter/types/bank/state.dart';
import '../../ui/base/songs/widgets/filter/types/key/state.dart';
import '../../ui/base/songs/widgets/filter/types/multiselect-tags/state.dart';
import '../../ui/base/songs/widgets/filter/types/search/state.dart';
import 'filter.dart';

part 'facet.g.dart';

/// How long the facets wait after the query changes, so a keystroke does not
/// run one scan per visible card. A provider so tests can drop the delay.
@Riverpod(keepAlive: true)
Duration facetDebounceDuration(Ref ref) => const Duration(milliseconds: 250);

/// The query the facets reflect: the list's search and filters.
typedef FacetQuery = ({
  String searchString,
  List<String> searchFields,
  Map<String, List<String>> filters,
  Set<String> bankFilters,
  KeyFilters keyFilters,
});

/// Matching keys, split so the key card can offer pitch, mode or full key.
typedef AvailableKeys = ({
  Set<KeyField> keys,
  Set<String> pitches,
  Set<String> modes,
});

/// Debounces [FacetQuery]: only the settled query reaches the facets.
@Riverpod(keepAlive: true)
Future<FacetQuery> debouncedFacetQuery(Ref ref) async {
  final query = (
    searchString: sanitize(ref.watch(searchStringStateProvider)),
    searchFields: ref.watch(searchFieldsStateProvider),
    filters: ref.watch(multiselectTagsFilterStateProvider),
    bankFilters: ref.watch(banksFilterStateProvider),
    keyFilters: ref.watch(keyFilterStateProvider),
  );
  await Future<void>.delayed(ref.watch(facetDebounceDurationProvider));
  return query;
}

/// Values of a multiselect [field] the current query can still reach. The
/// field's own selection is left out so siblings survive.
///
/// Auto-dispose, so a card scrolled out of the list stops querying.
@riverpod
Stream<Set<String>> fieldFacet(Ref ref, String field) async* {
  final query = await ref.watch(debouncedFacetQueryProvider.future);
  final built = _fieldFacetQuery(query, field);
  yield* _watchValues(built.sql, built.variables);
}

/// Banks the current query can still reach (own selection left out).
@riverpod
Stream<Set<String>> bankFacet(Ref ref) async* {
  final query = await ref.watch(debouncedFacetQueryProvider.future);
  final candidate = _candidate(query);
  final extra = filterWhere(query.filters, const {}, query.keyFilters);
  final sql =
      '${candidate.cte}SELECT DISTINCT songs.source_bank AS value '
      'FROM songs${candidate.join} WHERE '
      '${_where([candidate.condition, extra.where, _nonBlank('songs.source_bank')])} '
      'ORDER BY value';
  yield* _watchValues(sql, _variables(candidate, extra.variables));
}

/// Keys the current query can still reach, as pitches, modes and full keys.
@riverpod
Stream<AvailableKeys> keyFacet(Ref ref) async* {
  final query = await ref.watch(debouncedFacetQueryProvider.future);
  final candidate = _candidate(query);
  final extra = filterWhere(query.filters, query.bankFilters, noKeyFilters);
  final sql =
      '${candidate.cte}SELECT DISTINCT entry.value AS value '
      'FROM songs CROSS JOIN $_keyElements AS entry'
      '${candidate.join} WHERE '
      '${_where([candidate.condition, extra.where, "songs.key_field <> ''", "TRIM(entry.value) <> ''"])} '
      'ORDER BY value';
  yield* _watchValues(
    sql,
    _variables(candidate, extra.variables),
  ).map(_parseKeys);
}

/// `key_field` holds `pitch-mode` keys joined with ', '; JSON lets `json_each`
/// split it into one row per key.
const _keyElements =
    "json_each('[\"' || replace(songs.key_field, ', ', '\",\"') || '\"]')";

SearchCandidate _candidate(FacetQuery query) => SongFtsIndex.searchCandidate(
  term: query.searchString,
  fields: searchableFields(query.searchFields),
);

/// Binds in appearance order: MATCH, the candidate LIKEs, the caller filters.
List<Variable> _variables(SearchCandidate candidate, List<Variable> extra) => [
  ...candidate.variables,
  ...candidate.likeVariables,
  ...extra,
];

String _where(List<String> conditions) =>
    conditions.where((c) => c.isNotEmpty).join(' AND ');

String _nonBlank(String expression) => "TRIM(CAST($expression AS TEXT)) <> ''";

({String sql, List<Variable> variables}) _fieldFacetQuery(
  FacetQuery query,
  String field,
) {
  final candidate = _candidate(query);
  // Drop this field's own selection so siblings stay selectable.
  final extra = filterWhere(
    {...query.filters}..remove(field),
    query.bankFilters,
    query.keyFilters,
  );
  // `json_each(json, path)` yields one row per array element and one for a
  // scalar, so list and text fields share a shape.
  final sql =
      '${candidate.cte}SELECT DISTINCT entry.value AS value '
      "FROM songs CROSS JOIN json_each(songs.content_map, '\$.$field') AS entry"
      '${candidate.join} WHERE '
      '${_where([candidate.condition, extra.where, _nonBlank('entry.value')])} '
      'ORDER BY value';
  return (sql: sql, variables: _variables(candidate, extra.variables));
}

Stream<Set<String>> _watchValues(String sql, List<Variable> variables) => db
    .customSelect(sql, variables: variables, readsFrom: {db.songs})
    .watch()
    .map((rows) => {for (final row in rows) row.read<String>('value')});

AvailableKeys _parseKeys(Set<String> values) {
  final keys = <KeyField>{};
  final pitches = <String>{};
  final modes = <String>{};
  for (final value in values) {
    final key = KeyField.fromString(value);
    if (key == null) continue;
    keys.add(key);
    pitches.add(key.pitch);
    modes.add(key.mode);
  }
  return (keys: keys, pitches: pitches, modes: modes);
}
