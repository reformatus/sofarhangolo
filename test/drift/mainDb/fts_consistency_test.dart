import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';

/// Guards the FTS write path: upsert via `ON CONFLICT(uuid) DO UPDATE`, never
/// `InsertMode.insertOrReplace` (REPLACE skips the DELETE triggers and orphans
/// the FTS entry).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LyricDatabase db;

  setUp(() async {
    db = LyricDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Song songWith(String uuid, String title, String composer) => Song(
    uuid: uuid,
    title: title,
    lyrics: '$title szövege',
    keyField: const [],
    contentMap: {'composer': composer},
  );

  // The row class has no id, so the conflict target must be uuid; read the
  // rowid through raw SQL.
  Future<int> onlyRowid() async {
    final row = await db.customSelect('SELECT id FROM songs').getSingle();
    return row.read<int>('id');
  }

  /// The production upsert: insert by uuid, updating in place on conflict.
  Future<void> upsert(Song song) => db
      .into(db.songs)
      .insert(song, onConflict: DoUpdate((_) => song, target: [db.songs.uuid]));

  test('insert triggers populate the FTS index', () async {
    await upsert(songWith('a', 'Első dal', 'Kiss Áron'));

    final matches = await db
        .customSelect("SELECT rowid FROM songs_fts WHERE songs_fts MATCH 'elso'")
        .get();
    expect(matches, hasLength(1));
  });

  test('re-upserting an existing uuid keeps the FTS index consistent', () async {
    await upsert(songWith('a', 'Első dal', 'Kiss Áron'));
    final rowidBefore = await onlyRowid();

    // Second write for the same uuid, as the variation merge does.
    await upsert(songWith('a', 'Második dal', 'Kiss Áron'));

    expect(await db.select(db.songs).get(), hasLength(1));
    // The rowid must survive, otherwise the FTS entry is orphaned.
    expect(await onlyRowid(), rowidBefore);

    // Old title is gone from the index, new title is findable.
    final stale = await db
        .customSelect("SELECT rowid FROM songs_fts WHERE songs_fts MATCH 'elso'")
        .get();
    expect(stale, isEmpty);
    final fresh = await db
        .customSelect(
          "SELECT rowid FROM songs_fts WHERE songs_fts MATCH 'masodik'",
        )
        .get();
    expect(fresh, hasLength(1));

    // `rank` makes it check the content table too, which is what broke.
    await db.customStatement(
      "INSERT INTO songs_fts(songs_fts, rank) VALUES('integrity-check', 1)",
    );
  });

  test('deleting a song drops its FTS entry', () async {
    await upsert(songWith('a', 'Első dal', 'Kiss Áron'));
    await (db.delete(db.songs)..where((t) => t.uuid.equals('a'))).go();

    final matches = await db
        .customSelect("SELECT rowid FROM songs_fts WHERE songs_fts MATCH 'aron'")
        .get();
    expect(matches, isEmpty);
    await db.customStatement(
      "INSERT INTO songs_fts(songs_fts, rank) VALUES('integrity-check', 1)",
    );
  });
}
