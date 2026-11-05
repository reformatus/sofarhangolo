import 'package:drift/drift.dart';
import 'package:uuid/v4.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';

/// The bank-independent reference scheme used in local songs' contentMap
/// values to point at their attachments, which live in the assets table
/// under this exact sourceUrl.
String localAssetReference(String assetUuid) => 'local://$assetUuid';

Future<Song> _storedSong(String songUuid) async {
  final song = await (db.songs.select()..where((s) => s.uuid.equals(songUuid)))
      .getSingleOrNull();
  if (song == null) {
    throw StateError('Local song $songUuid does not exist.');
  }
  return song;
}

Future<void> _writeContentMap(String songUuid, Map<String, Object> map) =>
    (db.songs.update()..where((s) => s.uuid.equals(songUuid))).write(
      SongsCompanion(contentMap: Value(map)),
    );

/// Stores an attachment for a local song: writes the content into the
/// assets table under a fresh [localAssetReference] and points the song's
/// [fieldName] contentMap entry at it, all in one transaction. Returns the
/// song as stored afterwards; throws a [StateError] (writing nothing) when
/// the song does not exist.
Future<Song> writeLocalSongAsset(
  String songUuid,
  String fieldName,
  Uint8List content,
) {
  final reference = localAssetReference(UuidV4().generate());

  return db.transaction(() async {
    final song = await _storedSong(songUuid);

    await db.assets.deleteWhere(
      (a) => a.songUuid.equals(songUuid) & a.fieldName.equals(fieldName),
    );
    await db.assets.insert().insert(
      AssetsCompanion.insert(
        songUuid: songUuid,
        fieldName: fieldName,
        sourceUrl: reference,
        content: content,
      ),
    );
    await _writeContentMap(songUuid, {
      ...song.contentMap,
      fieldName: reference,
    });
    return _storedSong(songUuid);
  });
}

/// Removes an attachment from a local song: deletes its asset row and drops
/// the [fieldName] contentMap entry, so asset views treat it as unattached.
/// One transaction; returns the stored song, throws a [StateError] (writing
/// nothing) when the song does not exist.
Future<Song> removeLocalSongAsset(String songUuid, String fieldName) {
  return db.transaction(() async {
    final song = await _storedSong(songUuid);

    await db.assets.deleteWhere(
      (a) => a.songUuid.equals(songUuid) & a.fieldName.equals(fieldName),
    );
    await _writeContentMap(songUuid, {...song.contentMap}..remove(fieldName));
    return _storedSong(songUuid);
  });
}
