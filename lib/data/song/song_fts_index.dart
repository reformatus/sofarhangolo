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

  /// The `SELECT` list of a search query: the song's uuid (the row class has
  /// no id), relevance rank and one snippet per searchable column (aliased
  /// `match_<column>`). Callers join the uuids back to typed songs.
  String get searchColumns {
    final bm25Args = columns.map((c) => c.weight.toString()).join(', ');
    return [
      'songs.uuid AS uuid',
      'bm25($tableName, $bm25Args) AS rank',
      for (final (i, column) in columns.indexed)
        'snippet($tableName, $i, \'$snippetStart\', \'$snippetEnd\', \'...\', 30) '
            'AS match_${column.name}',
    ].join(', ');
  }

  /// The search query's `FROM`, joining hits back to their songs.
  String get searchFrom => 'FROM $tableName INNER JOIN songs ON $tableName.rowid = songs.id';

  /// Snippet column alias for [column].
  String matchAlias(SongFtsColumn column) => 'match_${column.name}';
}
