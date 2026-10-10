import 'package:diacritic/diacritic.dart';
import 'package:drift/drift.dart';

import 'song_fields.dart';

/// One column of the unified search index. Predefined fields (title, lyrics)
/// read from dedicated `songs` columns; mapped fields read from contentMap
/// through `json_extract`.
class SongFtsColumn {
  final String name;
  final String? jsonPath;
  final SongSearchGroup group;

  const SongFtsColumn(this.name, this.jsonPath, this.group);

  bool get isCore => jsonPath == null;

  /// Relative bm25 multiplier for this column.
  double get weight => group.weight;
}

/// The unified search index, derived from the field registry.
///
/// FTS5 columns are fixed per table, so a registry-dynamic layout cannot use
/// drift's generated table metadata — the index is app-managed: [ddl] is
/// generated from the registry, [ensure] reconciles the database against it on
/// open, and queries select columns from the same list. Drift still provides
/// the typed side: song rows are read through `selectOnly` + `readTable`.
class SongFtsIndex {
  static const viewName = 'songs_fts_content';
  static const tableName = 'songs_fts';
  static const triggerNames = ['songs_ai', 'songs_ad', 'songs_au'];
  static const snippetStart = '<?';
  static const snippetEnd = '?>';

  final List<SongFtsColumn> columns;

  const SongFtsIndex(this.columns);

  /// Builds the index layout from the registry: every field marked with the
  /// text search use, in registry order. Title and lyrics are core fields, so
  /// they are backed by their own columns.
  factory SongFtsIndex.fromRegistry([
    Map<String, SongField>? registry,
  ]) {
    return SongFtsIndex([
      for (final field in (registry ?? defaultSongFieldRegistry).values)
        if (field.hasSearchUse)
          SongFtsColumn(
            field.apiName,
            field.core ? null : field.apiName,
            field.searchGroup ?? SongSearchGroup.metadata,
          ),
    ]);
  }

  static final SongFtsIndex registry = SongFtsIndex.fromRegistry();

  String get _columnNames => columns.map((c) => c.name).join(', ');

  /// Expression reading one column's value, either bare (view) or from a
  /// `new`/`old` row (triggers). Core columns read their dedicated column,
  /// mapped ones `json_extract` their contentMap entry.
  String _expression(SongFtsColumn column, {String prefix = ''}) {
    final jsonPath = column.jsonPath;
    return jsonPath == null
        ? '$prefix${column.name}'
        : "json_extract(${prefix}content_map, '\$.$jsonPath')";
  }

  String _rowValues(String row) => [
    row == 'new' ? 'new.id' : 'old.id',
    for (final column in columns) _expression(column, prefix: '$row.'),
  ].join(', ');

  String get _viewSelect => [
    'id',
    for (final column in columns)
      if (column.isCore)
        column.name
      else
        '${_expression(column)} AS ${column.name}',
  ].join(', ');

  /// DDL for every object the index owns, keyed by object name. Comparing the
  /// generated statements against `sqlite_master` doubles as the layout
  /// signature, so [ensure] needs no extra bookkeeping.
  Map<String, String> get ddl => {
    viewName: 'CREATE VIEW $viewName AS SELECT $_viewSelect FROM songs',
    tableName:
        'CREATE VIRTUAL TABLE $tableName USING fts5'
        "($_columnNames, content='$viewName', content_rowid='id', "
        "tokenize='trigram remove_diacritics 1')",
    'songs_ai':
        'CREATE TRIGGER songs_ai AFTER INSERT ON songs BEGIN '
        'INSERT INTO $tableName(rowid, $_columnNames) '
        'VALUES (${_rowValues('new')}); END',
    'songs_ad':
        'CREATE TRIGGER songs_ad AFTER DELETE ON songs BEGIN '
        'INSERT INTO $tableName($tableName, rowid, $_columnNames) '
        "VALUES ('delete', ${_rowValues('old')}); END",
    'songs_au':
        'CREATE TRIGGER songs_au AFTER UPDATE ON songs BEGIN '
        'INSERT INTO $tableName($tableName, rowid, $_columnNames) '
        "VALUES ('delete', ${_rowValues('old')}); "
        'INSERT INTO $tableName(rowid, $_columnNames) '
        'VALUES (${_rowValues('new')}); END',
  };

  /// Reconciles the search index with [ddl]. Cheap no-op when the database
  /// already carries the current layout; otherwise drops and recreates the
  /// index objects and rebuilds the index from the content view.
  ///
  /// Returns whether anything was rebuilt, for logging and tests.
  Future<bool> ensure(DatabaseConnectionUser db) async {
    final ddl = this.ddl;
    final expected = {
      for (final entry in ddl.entries) entry.key: _canonical(entry.value),
    };

    final placeholders = List.filled(expected.length, '?').join(', ');
    final rows = await db
        .customSelect(
          'SELECT name, sql FROM sqlite_master WHERE name IN ($placeholders)',
          variables: [for (final name in expected.keys) Variable<String>(name)],
        )
        .get();
    final actual = {
      for (final row in rows)
        row.read<String>('name'): _canonical(row.read<String?>('sql') ?? ''),
    };

    final upToDate =
        actual.length == expected.length &&
        expected.entries.every((e) => actual[e.key] == e.value);
    if (upToDate) return false;

    // Triggers reference the index, so drop them first; recreate view first
    // (the index names it as its content source) and rebuild at the end.
    for (final name in triggerNames) {
      await db.customStatement('DROP TRIGGER IF EXISTS $name');
    }
    await db.customStatement('DROP TABLE IF EXISTS $tableName');
    await db.customStatement('DROP VIEW IF EXISTS $viewName');

    await db.customStatement(ddl[viewName]!);
    await db.customStatement(ddl[tableName]!);
    for (final name in triggerNames) {
      await db.customStatement(ddl[name]!);
    }
    await db.customStatement(
      "INSERT INTO $tableName($tableName) VALUES('rebuild')",
    );
    return true;
  }

  /// Collapses whitespace and drops a trailing semicolon so generated DDL
  /// compares equal to what SQLite stores in `sqlite_master`.
  static String _canonical(String sql) {
    return sql.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll(';', '');
  }

  /// Hungarian accent folding, mirroring `removeDiacritics(...).toLowerCase()`
  /// on the Dart side. SQLite's `lower()` folds ASCII only, so both cases of
  /// every accented letter are mapped explicitly (a fixed Hungarian set — the
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
      sql = "replace(replace($sql, '${entry.key}', '${entry.value}'), "
          "'${entry.key.toUpperCase()}', '${entry.value}')";
    }
    return sql;
  }

  String _foldedValue(SongFtsColumn column) =>
      foldExpression(_expression(column, prefix: 'songs.'));

  /// The `snippet()` columns of the FTS subquery, aliased `snippet_<field>`.
  String get _snippetSelects => [
    for (final (i, column) in columns.indexed)
      'snippet($tableName, $i, \'$snippetStart\', \'$snippetEnd\', '
          "'...', 30) AS snippet_${column.name}",
  ].join(', ');

  /// Folds a search term the same way [foldExpression] folds database values:
  /// diacritics removed, lowercased.
  static String foldTerm(String term) => removeDiacritics(term).toLowerCase();

  /// Builds the integrated search statement: FTS ∪ LIKE ∪ exact, tiered
  /// (0 exact, 1 LIKE, 2 FTS-only) and ordered by tier, relevance, folded
  /// title (then rowid, so [limit]/[offset] pages are stable). [fields] are
  /// the searchable columns taking part; [extraWhere] and [extraVariables]
  /// append caller filters (tags, banks).
  ///
  /// The FTS part lives in a subquery because FTS5 rejects `MATCH` in an OR
  /// over a left join; that subquery also computes `bm25` and the snippets.
  ///
  /// Prepared-statement variables are bound positionally, so their order must
  /// follow the placeholders in the SQL text: exact conditions, LIKE
  /// conditions, the FTS match, the WHERE LIKE conditions, extras, then the
  /// limit and offset.
  ({String sql, List<Variable> variables}) buildSearchQuery({
    required String term,
    required List<SongFtsColumn> fields,
    required int limit,
    int offset = 0,
    String extraWhere = '',
    List<Variable> extraVariables = const [],
  }) {
    assert(fields.isNotEmpty, 'at least one searchable field must take part');

    final foldedTerm = foldTerm(term);
    final likePattern = '%${_escapeLike(foldedTerm)}%';
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

    final matchString = fields.length == columns.length
        ? term
        : '{${fields.map((field) => field.name).join(' ')}} : $term';
    variables.add(Variable<String>(matchString));

    final whereLike = <String>[];
    for (final field in fields) {
      whereLike.add("${_foldedValue(field)} LIKE ? ESCAPE '\\'");
      variables.add(Variable<String>(likePattern));
    }
    variables.addAll(extraVariables);
    variables
      ..add(Variable<int>(limit))
      ..add(Variable<int>(offset));

    final sql =
        'SELECT songs.uuid AS uuid, '
        'hit.rank AS rank, '
        'CASE WHEN ${exact.join(' OR ')} THEN 0 '
        'WHEN ${like.join(' OR ')} THEN 1 ELSE 2 END AS tier, '
        '${[
          for (final column in columns)
            'hit.snippet_${column.name} AS ${matchAlias(column)}',
        ].join(', ')} '
        'FROM songs '
        'LEFT JOIN ('
        'SELECT rowid AS id, '
        'bm25($tableName, ${columns.map((c) => c.weight).join(', ')}) AS rank, '
        '$_snippetSelects '
        'FROM $tableName WHERE $tableName MATCH ?'
        ') AS hit ON hit.id = songs.id '
        'WHERE hit.id IS NOT NULL OR ${whereLike.join(' OR ')}'
        '${extraWhere.isEmpty ? '' : ' AND ($extraWhere)'} '
        'ORDER BY tier, COALESCE(hit.rank, 0), '
        '${foldExpression('songs.title')}, songs.id '
        'LIMIT ? OFFSET ?';

    return (sql: sql, variables: variables);
  }

  /// Escapes LIKE wildcards so the term is matched literally.
  static String _escapeLike(String term) => term
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// Snippet column alias for [column].
  String matchAlias(SongFtsColumn column) => 'match_${column.name}';
}
