import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';

/// The attachment value for [bytes] in a local song's contentMap: the
/// lowercase md5 hex of the content, so identical files give identical
/// values (and identical song hashes) on every device.
String localAssetHash(List<int> bytes) => md5.convert(bytes).toString();

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

/// Stores an attachment for a local song: upserts the (song, [fieldName])
/// row of the assets table with the content and sets the song's [fieldName]
/// contentMap entry to its [localAssetHash], all in one transaction. Returns the
/// song as stored afterwards; throws a [StateError] (writing nothing) when
/// the song does not exist.
Future<Song> writeLocalSongAsset(
  String songUuid,
  String fieldName,
  Uint8List content,
) {
  final hash = localAssetHash(content);

  return db.transaction(() async {
    final song = await _storedSong(songUuid);

    await db.assets.deleteWhere(
      (a) => a.songUuid.equals(songUuid) & a.fieldName.equals(fieldName),
    );
    await db.assets.insert().insert(
      AssetsCompanion.insert(
        songUuid: songUuid,
        fieldName: fieldName,
        content: content,
      ),
    );
    await _writeContentMap(songUuid, {...song.contentMap, fieldName: hash});
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
