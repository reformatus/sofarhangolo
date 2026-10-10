import 'package:drift/drift.dart';
import 'package:uuid/v4.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';

/// The bank-independent reference scheme used in local songs' contentMap
/// values to point at their attachments, which live in the assets table
/// under this exact sourceUrl.
String localAssetReference(String assetUuid) => 'local://$assetUuid';

/// Stores an attachment for a local song: writes the content into the
/// assets table under a fresh [localAssetReference] and points the song's
/// [fieldName] contentMap entry at it.
Future<void> writeLocalSongAsset(
  Song song,
  String fieldName,
  Uint8List content,
) async {
  final reference = localAssetReference(UuidV4().generate());

  await db.assets.deleteWhere(
    (a) => a.songUuid.equals(song.uuid) & a.fieldName.equals(fieldName),
  );
  await db.assets.insert().insert(
    AssetsCompanion.insert(
      songUuid: song.uuid,
      fieldName: fieldName,
      sourceUrl: reference,
      content: content,
    ),
  );

  song.contentMap = {...song.contentMap, fieldName: reference};
  await (db.songs.update()..where((s) => s.uuid.equals(song.uuid))).write(
    SongsCompanion(contentMap: Value(song.contentMap)),
  );
}

/// Removes an attachment from a local song: deletes its asset row and drops
/// the [fieldName] contentMap entry, so asset views treat it as unattached.
Future<void> removeLocalSongAsset(Song song, String fieldName) async {
  await db.assets.deleteWhere(
    (a) => a.songUuid.equals(song.uuid) & a.fieldName.equals(fieldName),
  );

  song.contentMap = {...song.contentMap}..remove(fieldName);
  await (db.songs.update()..where((s) => s.uuid.equals(song.uuid))).write(
    SongsCompanion(contentMap: Value(song.contentMap)),
  );
}
