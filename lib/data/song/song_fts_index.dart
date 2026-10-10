import 'package:diacritic/diacritic.dart';
import 'package:drift/drift.dart';

import 'song_fields.dart';

/// One column of the drift-declared search index (see song.drift). Its position
/// in [SongFtsIndex.columns] is the `snippet()` column index and the bm25
/// weight position.
class SongFtsColumn {
  final String name;
  final SongSearchGroup group;

  const SongFtsColumn(this.name, this.group);

  double get weight => group.weight;
}

/// Builds the unified text search query on top of the drift-owned FTS index.
///
/// Only `title` and `lyrics` live in `songs_fts` (song.drift) - the two long
/// columns the index is actually worth. Every other searchable field is matched
/// by expression over `songs` (folded LIKE and exact equality), so the index
/// layout is static and needs no dynamic DDL or runtime reconciliation.
///
/// Hits are tiered - 0 exact, 1 substring, 2 FTS-only - then ordered by bm25,
/// the folded title and finally the rowid, so LIMIT/OFFSET pages stay stable.
/// The FTS part lives in a subquery because FTS5 rejects `MATCH` inside an OR
/// over a left join; that subquery also computes `bm25` and the snippets.
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

  /// Fields backed by a dedicated `songs` column; every other searchable field
  /// is read from `content_map`.
  static const Set<String> coreFields = {'title', 'lyrics'};

  static bool isFtsField(String field) => _ftsFieldNames.contains(field);

  /// The SQL expression reading [field]'s searchable value.
  static String valueExpression(String field) => coreFields.contains(field)
      ? 'songs.$field'
      : "json_extract(songs.content_map, '\$.$field')";

  /// Hungarian accent folding, mirroring `removeDiacritics(...).toLowerCase()`
  /// on the Dart side. SQLite's `lower()` folds ASCII only, so both cases of
  /// every accented letter are mapped explicitly (a fixed Hungarian set - the
  /// FTS tokenizer's `remove_diacritics` handles the rest when matching).
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

  /// Wraps [expression] in the fold chain (see [_foldReplacements]), used for
  /// LIKE/exact matching and folded-title ordering.
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

  /// Folds a search term the same way [foldExpression] folds database values:
  /// diacritics removed, lowercased.
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

  /// The `{a b} : term` match string restricting MATCH to [ftsFields]; the bare
  /// term when every column takes part.
  static String _matchString(String term, List<String> ftsFields) =>
      ftsFields.length == columns.length
      ? term
      : '{${ftsFields.join(' ')}} : $term';

  /// Builds the integrated search statement: FTS ∪ LIKE ∪ exact, tiered
  /// (0 exact, 1 LIKE, 2 FTS-only) and ordered by tier, relevance, folded
  /// title (then rowid, so [limit]/[offset] pages are stable). [fields] are
  /// the searchable field names taking part; [extraWhere] and [extraVariables]
  /// append caller filters (tags, banks, key).
  ///
  /// Prepared-statement variables are bound positionally, so their order must
  /// follow the placeholders in the SQL text: exact conditions, LIKE
  /// conditions, the FTS match, the WHERE LIKE conditions, extras, then the
  /// limit and offset.
  static ({String sql, List<Variable> variables}) buildSearchQuery({
    required String term,
    required List<String> fields,
    required int limit,
    int offset = 0,
    String extraWhere = '',
    List<Variable> extraVariables = const [],
  }) {
    assert(fields.isNotEmpty, 'at least one searchable field must take part');

    final foldedTerm = foldTerm(term);
    final likePattern = '%${_escapeLike(foldedTerm)}%';
    final ftsFields = _ftsFieldsOf(fields);
    final hasFts = ftsFields.isNotEmpty;

    final variables = <Variable>[];

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

    var from = 'FROM songs';
    if (hasFts) {
      variables.add(Variable<String>(_matchString(term, ftsFields)));
      from =
          'FROM songs LEFT JOIN ('
          'SELECT rowid AS id, '
          'bm25($tableName, ${columns.map((c) => c.weight).join(', ')}) AS rank, '
          '$_snippetSelects '
          'FROM $tableName WHERE $tableName MATCH ?'
          ') AS hit ON hit.id = songs.id';
    }

    final whereLike = <String>[];
    for (final field in fields) {
      whereLike.add("${_foldedValue(field)} LIKE ? ESCAPE '\\'");
      variables.add(Variable<String>(likePattern));
    }
    variables.addAll(extraVariables);
    variables
      ..add(Variable<int>(limit))
      ..add(Variable<int>(offset));

    final matchCondition = hasFts
        ? '(hit.id IS NOT NULL OR ${whereLike.join(' OR ')})'
        : '(${whereLike.join(' OR ')})';
    final rankColumn = hasFts ? 'hit.rank AS rank' : 'NULL AS rank';
    final matches = [
      for (final column in columns)
        hasFts
            ? 'hit.${matchAlias(column.name)} AS ${matchAlias(column.name)}'
            : 'NULL AS ${matchAlias(column.name)}',
    ].join(', ');
    // A bare integer in ORDER BY is a column ordinal, so use NULL as the
    // neutral constant when there is no FTS rank.
    final rankOrder = hasFts ? 'COALESCE(hit.rank, 0)' : 'NULL';

    final sql =
        'SELECT songs.uuid AS uuid, '
        '$rankColumn, '
        'CASE WHEN ${exact.join(' OR ')} THEN 0 '
        'WHEN ${like.join(' OR ')} THEN 1 ELSE 2 END AS tier, '
        '$matches '
        '$from '
        'WHERE $matchCondition'
        '${extraWhere.isEmpty ? '' : ' AND ($extraWhere)'} '
        'ORDER BY tier, $rankOrder, '
        '${foldExpression('songs.title')}, songs.id '
        'LIMIT ? OFFSET ?';

    return (sql: sql, variables: variables);
  }

  /// A `SELECT COUNT(*)` query over every row matching the current search (when
  /// [term] is non-empty) and [extraWhere] filters - no ordering, snippets or
  /// limit. Used for the result count in the filters subtitle.
  static ({String sql, List<Variable> variables}) countQuery({
    String? term,
    List<String> fields = const [],
    String extraWhere = '',
    List<Variable> extraVariables = const [],
  }) {
    final searching = term != null && term.isNotEmpty;
    final variables = <Variable>[];
    final conditions = <String>[];

    var from = 'FROM songs';
    if (searching) {
      assert(fields.isNotEmpty, 'at least one searchable field must take part');
      // Textual order: the MATCH inside the join subquery first, then the
      // LIKE conditions, then the caller's filters.
      final ftsFields = _ftsFieldsOf(fields);
      final hasFts = ftsFields.isNotEmpty;
      if (hasFts) {
        variables.add(Variable<String>(_matchString(term, ftsFields)));
        from =
            'FROM songs LEFT JOIN (SELECT rowid AS id FROM $tableName '
            'WHERE $tableName MATCH ?) AS hit ON hit.id = songs.id';
      }

      final like = <String>[];
      final likePattern = '%${_escapeLike(foldTerm(term))}%';
      for (final field in fields) {
        like.add("${_foldedValue(field)} LIKE ? ESCAPE '\\'");
        variables.add(Variable<String>(likePattern));
      }
      conditions.add(
        hasFts
            ? '(hit.id IS NOT NULL OR ${like.join(' OR ')})'
            : '(${like.join(' OR ')})',
      );
    }

    if (extraWhere.isNotEmpty) {
      conditions.add('($extraWhere)');
      variables.addAll(extraVariables);
    }

    final where = conditions.isEmpty
        ? ''
        : ' WHERE ${conditions.join(' AND ')}';
    return (sql: 'SELECT COUNT(*) AS count $from$where', variables: variables);
  }
}
