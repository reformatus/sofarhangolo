import 'package:diacritic/diacritic.dart';
import 'package:drift/drift.dart';

import 'song_fields.dart';

/// One column of the search index (song.drift). Its position in
/// [SongFtsIndex.columns] is the `snippet()` column index and bm25 weight.
class SongFtsColumn {
  final String name;
  final SongSearchGroup group;

  const SongFtsColumn(this.name, this.group);

  double get weight => group.weight;
}

/// Builds the unified text search query on top of the FTS index.
///
/// Only `title` and `lyrics` live in `songs_fts` (song.drift); every other
/// searchable field matches by expression over `songs`, so the index layout is
/// static. Hits are tiered (0 exact, 1 substring, 2 FTS-only) then ordered by
/// bm25, folded title and rowid for stable paging. The FTS set is a
/// `MATERIALIZED` CTE (FTS5 rejects `MATCH` in an OR over a left join) so bm25
/// and snippets compute once per query, and `COUNT(*) OVER ()` carries the
/// total before `LIMIT`.
class SongFtsIndex {
  static const tableName = 'songs_fts';
  static const snippetStart = '<?';
  static const snippetEnd = '?>';

  /// The FTS columns, in song.drift's declaration order.
  static const List<SongFtsColumn> columns = [
    SongFtsColumn('title', SongSearchGroup.title),
    SongFtsColumn('lyrics', SongSearchGroup.lyrics),
  ];

  static final Set<String> _ftsFieldNames = {
    for (final column in columns) column.name,
  };

  /// Fields read from a `songs` column; the rest come from `content_map`.
  static const Set<String> coreFields = {'title', 'lyrics'};

  static bool isFtsField(String field) => _ftsFieldNames.contains(field);

  /// The SQL expression reading [field]'s searchable value.
  static String valueExpression(String field) => coreFields.contains(field)
      ? 'songs.$field'
      : "json_extract(songs.content_map, '\$.$field')";

  /// Hungarian accent folding, mirroring `removeDiacritics(...).toLowerCase()`.
  /// `lower()` folds ASCII only, so both cases of each accented letter are
  /// mapped explicitly.
  static const _foldReplacements = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ö': 'o',
    'ő': 'o',
    'ú': 'u',
    'ü': 'u',
    'ű': 'u',
  };

  /// [expression] wrapped in the fold chain (see [_foldReplacements]).
  static String foldExpression(String expression) {
    var sql = 'lower($expression)';
    for (final entry in _foldReplacements.entries) {
      sql =
          "replace(replace($sql, '${entry.key}', '${entry.value}'), "
          "'${entry.key.toUpperCase()}', '${entry.value}')";
    }
    return sql;
  }

  static String _foldedValue(String field) =>
      foldExpression(valueExpression(field));

  /// The `snippet()` columns of the FTS subquery, aliased `match_<field>`.
  static String get _snippetSelects => [
    for (final (i, column) in columns.indexed)
      'snippet($tableName, $i, \'$snippetStart\', \'$snippetEnd\', '
          "'...', 30) AS ${matchAlias(column.name)}",
  ].join(', ');

  /// Folds a term the way [foldExpression] folds values.
  static String foldTerm(String term) => removeDiacritics(term).toLowerCase();

  /// Escapes LIKE wildcards so the term is matched literally.
  static String _escapeLike(String term) => term
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// Snippet column alias for [field].
  static String matchAlias(String field) => 'match_$field';

  /// The FTS columns among [fields], in declaration order.
  static List<String> _ftsFieldsOf(List<String> fields) => [
    for (final column in columns)
      if (fields.contains(column.name)) column.name,
  ];

  /// The match string restricting MATCH to [ftsFields]; the bare term when all
  /// columns take part.
  static String _matchString(String term, List<String> ftsFields) =>
      ftsFields.length == columns.length
      ? term
      : '{${ftsFields.join(' ')}} : $term';

  /// The candidate test every query shares: the FTS set as a `MATERIALIZED` CTE
  /// OR a folded LIKE per searchable field.
  ///
  /// Returned as fragments because callers place the condition differently; the
  /// binds split to match ([SearchCandidate.variables] precede the SELECT,
  /// [SearchCandidate.likeVariables] sit where the condition appears).
  ///
  /// [cteSelect] is the CTE's projection.
  static SearchCandidate searchCandidate({
    required String term,
    required List<String> fields,
    String cteSelect = 'rowid AS id',
  }) {
    if (term.isEmpty) return const SearchCandidate.empty();
    assert(fields.isNotEmpty, 'at least one searchable field must take part');

    final likePattern = '%${_escapeLike(foldTerm(term))}%';
    final likeConditions = [
      for (final field in fields) "${_foldedValue(field)} LIKE ? ESCAPE '\\'",
    ];
    final likeVariables = [
      for (var i = 0; i < fields.length; i++) Variable<String>(likePattern),
    ];
    final ftsFields = _ftsFieldsOf(fields);
    if (ftsFields.isEmpty) {
      return SearchCandidate(
        cte: '',
        join: '',
        condition: '(${likeConditions.join(' OR ')})',
        variables: const [],
        likeVariables: likeVariables,
      );
    }
    return SearchCandidate(
      cte:
          'WITH hit AS MATERIALIZED (SELECT $cteSelect FROM $tableName '
          'WHERE $tableName MATCH ?) ',
      join: ' LEFT JOIN hit ON hit.id = songs.id',
      condition: '(hit.id IS NOT NULL OR ${likeConditions.join(' OR ')})',
      variables: [Variable<String>(_matchString(term, ftsFields))],
      likeVariables: likeVariables,
    );
  }

  /// The integrated search statement: FTS ∪ LIKE ∪ exact, tiered (0 exact,
  /// 1 LIKE, 2 FTS-only) and ordered by tier, relevance, folded title, rowid.
  /// [extraWhere]/[extraVariables] append caller filters (tags, banks, key).
  ///
  /// Variables bind positionally, in SQL-text order: the CTE's MATCH, the exact
  /// conditions, the LIKE conditions, the WHERE LIKE conditions, extras, then
  /// the limit and offset.
  static ({String sql, List<Variable> variables}) buildSearchQuery({
    required String term,
    required List<String> fields,
    required int limit,
    int offset = 0,
    String extraWhere = '',
    List<Variable> extraVariables = const [],
  }) {
    assert(term.isNotEmpty, 'the search query is only used with a term');

    final foldedTerm = foldTerm(term);
    final likePattern = '%${_escapeLike(foldedTerm)}%';
    final candidate = searchCandidate(
      term: term,
      fields: fields,
      cteSelect:
          'rowid AS id, '
          'bm25($tableName, ${columns.map((c) => c.weight).join(', ')}) AS rank, '
          '$_snippetSelects',
    );
    final hasFts = candidate.cte.isNotEmpty;

    final variables = <Variable>[...candidate.variables];

    final exact = <String>[];
    final like = <String>[];
    for (final field in fields) {
      exact.add('${_foldedValue(field)} = ?');
      variables.add(Variable<String>(foldedTerm));
    }
    for (final field in fields) {
      like.add("${_foldedValue(field)} LIKE ? ESCAPE '\\'");
      variables.add(Variable<String>(likePattern));
    }

    variables.addAll(candidate.likeVariables);
    variables.addAll(extraVariables);
    variables
      ..add(Variable<int>(limit))
      ..add(Variable<int>(offset));

    // A bare integer in ORDER BY is a column ordinal, hence NULL.
    final rankColumn = hasFts ? 'hit.rank AS rank' : 'NULL AS rank';
    final matches = [
      for (final column in columns)
        hasFts
            ? 'hit.${matchAlias(column.name)} AS ${matchAlias(column.name)}'
            : 'NULL AS ${matchAlias(column.name)}',
    ].join(', ');
    final rankOrder = hasFts ? 'COALESCE(hit.rank, 0)' : 'NULL';

    final sql =
        '${candidate.cte}SELECT songs.uuid AS uuid, '
        'COUNT(*) OVER () AS total, '
        '$rankColumn, '
        'CASE WHEN ${exact.join(' OR ')} THEN 0 '
        'WHEN ${like.join(' OR ')} THEN 1 ELSE 2 END AS tier, '
        '$matches '
        'FROM songs${candidate.join} '
        'WHERE ${candidate.condition}'
        '${extraWhere.isEmpty ? '' : ' AND ($extraWhere)'} '
        'ORDER BY tier, $rankOrder, '
        '${foldExpression('songs.title')}, songs.id '
        'LIMIT ? OFFSET ?';

    return (sql: sql, variables: variables);
  }
}

/// Fragments of the shared candidate test ([SongFtsIndex.searchCandidate]).
class SearchCandidate {
  /// `''` or the `WITH hit AS MATERIALIZED (...)` prefix.
  final String cte;

  /// `''` or the `LEFT JOIN hit ...` to append after the caller's own joins.
  final String join;

  /// `''` (no term) or the condition to AND into the WHERE.
  final String condition;

  /// Binds for [cte]'s `MATCH`.
  final List<Variable> variables;

  /// Binds for [condition]'s LIKE placeholders, bound where it appears.
  final List<Variable> likeVariables;

  const SearchCandidate({
    required this.cte,
    required this.join,
    required this.condition,
    required this.variables,
    required this.likeVariables,
  });

  const SearchCandidate.empty()
    : cte = '',
      join = '',
      condition = '',
      variables = const [],
      likeVariables = const [];
}
