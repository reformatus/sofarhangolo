import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/song_fts_index.dart';

/// The search index is app-managed: its layout is generated from the field
/// registry and reconciled against the database on startup, outside drift's
/// schema. These tests cover that lifecycle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LyricDatabase db;

  setUp(() {
    db = LyricDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> indexSql(String name) async {
    final row = await db
        .customSelect(
          'SELECT sql FROM sqlite_master WHERE name = ?',
          variables: [Variable<String>(name)],
        )
        .getSingle();
    return row.read<String>('sql');
  }

  Song songWith(String uuid, String title, String composer) => Song(
    uuid: uuid,
    title: title,
    lyrics: '$title szövege',
    keyField: const [],
    contentMap: {'composer': composer},
  );

  test('creates the index from the registry, then stays a no-op', () async {
    expect(await db.ensureSearchIndex(), isTrue);
    expect(await db.ensureSearchIndex(), isFalse);

    final layout = await indexSql(SongFtsIndex.tableName);
    for (final column in SongFtsIndex.registry.columns) {
      expect(layout, contains(column.name), reason: column.name);
    }
    // Content comes from the generated view, not the songs table directly.
    expect(layout, contains("content='${SongFtsIndex.viewName}'"));
  });

  test('rebuilds a stale index layout', () async {
    await db.ensureSearchIndex();

    // Emulate an index from an older layout (a column the registry no longer
    // knows, and a missing one it does).
    await db.customStatement('DROP TABLE ${SongFtsIndex.tableName}');
    await db.customStatement(
      'CREATE VIRTUAL TABLE ${SongFtsIndex.tableName} '
      "USING fts5(legacy_column, content='', tokenize='trigram')",
    );

    expect(await db.ensureSearchIndex(), isTrue);
    final layout = await indexSql(SongFtsIndex.tableName);
    expect(layout, isNot(contains('legacy_column')));
    expect(layout, contains('composer'));
  });

  test('indexes songs that existed before the index was created', () async {
    await db.into(db.songs).insert(songWith('a', 'Első dal', 'Kiss Áron'));

    await db.ensureSearchIndex();

    final hits = await db
        .customSelect(
          "SELECT rowid FROM ${SongFtsIndex.tableName} "
          "WHERE ${SongFtsIndex.tableName} MATCH 'aron'",
        )
        .get();
    expect(hits, hasLength(1));
  });
}
