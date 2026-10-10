import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';

/// Guards the FTS write path: songs must be upserted with an explicit
/// `ON CONFLICT(uuid) DO UPDATE` (via [BankSongUpdateTask._upsertSong]),
/// never with `InsertMode.insertOrReplace`. REPLACE's implicit delete
/// skips DELETE triggers, orphaning the FTS entry for the old rowid and
/// breaking the index.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LyricDatabase db;

  setUp(() async {
    db = LyricDatabase(NativeDatabase.memory());
    // The search index is app-managed; create it like the app does at startup.
    await db.ensureSearchIndex();
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

  // The row class has no id, which is exactly why the conflict target must
  // be uuid — read the rowid through raw SQL when the test needs it.
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
        .customSelect(
          "SELECT rowid FROM songs_fts WHERE songs_fts MATCH 'composer : aron'",
        )
        .get();
    expect(matches, hasLength(1));
  });

  test('re-upserting an existing uuid keeps the FTS index consistent', () async {
    await upsert(songWith('a', 'Első dal', 'Kiss Áron'));
    final rowidBefore = await onlyRowid();

    // Second write for the same uuid — this is what the variation merge
    // does within a single update run.
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

    // Full FTS consistency against the content view (rank > 0 checks the
    // content table too, which is what broke with insertOrReplace).
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
