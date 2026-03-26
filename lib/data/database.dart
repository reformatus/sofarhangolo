import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'asset/asset.dart';
/*
// Used for debugging
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:path/path.dart' as p;
*/

import 'bank/bank.dart';
import 'cue/cue.dart';
import 'database.steps.dart';
import 'preferences/storage.dart';
import 'song/lyrics/format.dart';
import 'song/song.dart';

part 'database.g.dart';

late LyricDatabase db;
late final Directory dataDir;

@DriftDatabase(
  tables: [Songs, Banks, Assets, Cues, PreferenceStorage],
  include: {
    'song/song.drift',
    '../services/songs/filter.drift',
    '../services/key/select_distinct.drift',
  },
)
class LyricDatabase extends _$LyricDatabase {
  // LyricDatabase() : super(_openConnection()); //used for debugging
  LyricDatabase([QueryExecutor? executor])
    : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      // Examples for migrations at: https://github.com/simolus3/drift/blob/develop/examples/migrations_example/lib/database.dart#L58
      onUpgrade: stepByStep(
        from1To2: (m, schema) async {
          await m.drop(schema.songsFts);
          await m.drop(schema.songsAd);
          await m.drop(schema.songsAi);
          await m.drop(schema.songsAu);

          await m.dropColumn(schema.songs, 'composer');
          await m.dropColumn(schema.songs, 'lyricist');
          await m.dropColumn(schema.songs, 'translator');
          await m.dropColumn(schema.songs, 'user_note');

          await m.renameColumn(schema.songs, 'opensong', schema.songs.lyrics);
          await m.addColumn(schema.songs, schema.songs.lyricsFormat);

          await m.createTable(schema.songsFts);
          await m.createTrigger(schema.songsAd);
          await m.createTrigger(schema.songsAi);
          await m.createTrigger(schema.songsAu);
          await customStatement(
            "INSERT INTO songs_fts(songs_fts) VALUES('rebuild')",
          );

          // set bank updated to old date (to trigger in background refresh) - or make good way to do this
        },
        from2To3: (m, schema) async {
          await m.addColumn(schema.banks, schema.banks.failedSongUuids);
          await m.addColumn(schema.banks, schema.banks.totalSongsInBank);
        },
      ),
    );
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'lyric3');
  }
}

/*
// see https://drift.simonbinder.eu/setup/#database-class
// implemented for logStatemets capability, used for debugging
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'lyric.sqlite'));

    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;

    return NativeDatabase.createInBackground(file, logStatements: false);
  });
}
*/

// General db type converters

class UriConverter extends TypeConverter<Uri, String> {
  const UriConverter();

  @override
  Uri fromSql(String fromDb) {
    return Uri.parse(fromDb);
  }

  @override
  String toSql(Uri value) {
    return value.toString();
  }
}

class MapConverter extends TypeConverter<Map<String, dynamic>, String> {
  const MapConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    return jsonDecode(fromDb) as Map<String, dynamic>;
  }

  @override
  String toSql(Map<String, dynamic> value) {
    return jsonEncode(value);
  }
}

String sanitize(String s) =>
    s.replaceAll(RegExp(r'[^\p{Letter}\p{Number} ]', unicode: true), '').trim();
