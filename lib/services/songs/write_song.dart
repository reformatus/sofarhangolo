import 'package:drift/drift.dart';
import 'package:uuid/v4.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';
import 'delete_for_song.dart';

/// Creates a new local song, or updates an existing one by uuid.
///
/// Local songs are bank-independent ([Song.sourceBank] is null): they are
/// never touched by bank updates and can be freely edited.
Future<Song> writeLocalSong(Song song) async {
  if (song.sourceBank != null) {
    throw ArgumentError.value(
      song.sourceBank,
      'song.sourceBank',
      'writeLocalSong only accepts bank-independent local songs',
    );
  }

  final updatedRows = await (db.update(
    db.songs,
  )..where((s) => s.uuid.equals(song.uuid))).writeReturning(
    SongsCompanion(
      sourceBank: Value(song.sourceBank),
      contentMap: Value(song.contentMap),
      title: Value(song.title),
      lyrics: Value(song.lyrics),
      lyricsFormat: Value(song.lyricsFormat),
      variationOf: Value(song.variationOf),
      keyField: Value(song.keyField),
      originalSongUuid: Value(song.originalSongUuid),
      originalContentHash: Value(song.originalContentHash),
    ),
  );

  if (updatedRows.isEmpty) {
    await db.into(db.songs).insert(song);
  }
  return song;
}

/// Copies [song] (typically a bank song) into a new editable local song.
///
/// The copy:
/// - gets a fresh uuid and no bank linkage ([Song.sourceBank] is null),
/// - loses asset references (`svg`/`pdf`) from its content, so asset views
///   never try to fetch the original's bank assets for it,
/// - does not keep [Song.variationOf], so bank updates never treat it as a
///   variation of the original,
/// - remembers [song] via [Song.originalSongUuid] and the original's
///   [Song.stableContentHash] at copy time for change detection.
Future<Song> copySongToLocal(Song song) async {
  final local = Song(
    uuid: UuidV4().generate(),
    title: song.title,
    lyrics: song.lyrics,
    lyricsFormat: song.lyricsFormat,
    keyField: song.keyField,
    contentMap:
        Map.of(song.contentMap)
          ..remove('svg')
          ..remove('pdf'),
    originalSongUuid: song.uuid,
    originalContentHash: song.stableContentHash,
  );
  await db.into(db.songs).insert(local);
  return local;
}

/// Deletes a local song together with any cached assets.
Future<void> deleteLocalSong(Song song) async {
  await db.songs.deleteWhere((s) => s.uuid.equals(song.uuid));
  await deleteAssetsForSong(song);
}
