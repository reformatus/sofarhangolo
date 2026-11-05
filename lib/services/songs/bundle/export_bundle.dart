import 'package:drift/drift.dart';

import '../../../data/cue/cue.dart';
import '../../../data/database.dart';
import '../../../data/log/logger.dart';
import '../../../data/song/song.dart';
import '../../../data/song/song_link.dart';
import '../../assets/pick_asset.dart';
import '../../assets/write_song_asset.dart';
import '../../bank/banks.dart';
import '../write_song.dart';
import 'song_bundle.dart';

/// The uuids of the song slides of cue JSON (`Cue.toJson()` shape).
Iterable<String> cueSongUuids(Map cueJson) sync* {
  final content = cueJson['content'];
  if (content is! List) return;
  for (final slide in content) {
    if (slide is! Map || slide['slideType'] != 'song') continue;
    final song = slide['song'];
    final uuid = song is Map ? song['uuid'] : null;
    if (uuid is String && uuid.isNotEmpty) yield uuid;
  }
}

/// The uuids of the local-bank songs the slides of [cue] reference (the ones
/// a link cannot carry), in slide order without repeats.
Future<List<String>> cueLocalSongUuids(Cue cue) async {
  final uuids = cueSongUuids(cue.toJson()).toSet();
  if (uuids.isEmpty) return const [];
  final localUuid = (await localBank()).uuid;
  final rows =
      await (db.songs.select()
            ..where((s) => s.uuid.isIn(uuids) & s.sourceBank.equals(localUuid)))
          .get();
  final local = {for (final r in rows) r.uuid};
  return uuids.where(local.contains).toList();
}

/// Builds a song bundle (see [songBundleVersion]) of the local songs
/// [songUuids] plus, when [cue] is given, the cue and every local song its
/// slides reference. Uuids of songs that are not in the local bank (bank
/// songs travel by uuid only) or no longer exist are skipped silently.
///
/// Each exported song first gets a checkpoint of its current hash
/// ([addLocalSongCheckpoint]), so the exported list includes it.
Future<Uint8List> exportSongBundle(List<String> songUuids, {Cue? cue}) async {
  final cueJson = cue?.toJson();
  final wanted = <String>{
    ...songUuids,
    if (cueJson != null) ...cueSongUuids(cueJson),
  };

  final localUuid = (await localBank()).uuid;
  final songs = <Song>[];
  for (final uuid in wanted) {
    final row = await (db.songs.select()..where((s) => s.uuid.equals(uuid)))
        .getSingleOrNull();
    if (row == null || row.sourceBank != localUuid) continue;
    songs.add(await addLocalSongCheckpoint(uuid));
  }

  final songJson = <Map<String, Object?>>[];
  final assetsByMd5 = <String, Uint8List>{};
  for (final song in songs) {
    for (final field in assetFieldExtensions.keys) {
      if (song.contentMap[field] == null) continue;
      final asset =
          await (db.assets.select()..where(
                (a) => a.songUuid.equals(song.uuid) & a.fieldName.equals(field),
              ))
              .getSingleOrNull();
      if (asset == null) {
        log.warning('Hiányzó csatolmány exportáláskor: ${song.uuid} $field');
        continue;
      }
      // Named by its real hash: a corrupted local file is then dropped (and
      // reported) by the recipient instead of being trusted.
      assetsByMd5[localAssetHash(asset.content)] = asset.content;
    }
    songJson.add(await _songEntry(song));
  }

  return writeSongBundle(
    songJson: songJson,
    assetsByMd5: assetsByMd5,
    cue: cueJson,
  );
}

Future<Map<String, Object?>> _songEntry(Song song) async {
  final link =
      await (db.songLinks.select()..where(
            (l) =>
                l.sourceUuid.equals(song.uuid) &
                l.type.equals(SongLinkType.localCopyOf.index),
          ))
          .getSingleOrNull();

  Map<String, Object?>? origin;
  if (link != null) {
    final bankSong =
        await (db.songs.select()..where((s) => s.uuid.equals(link.targetUuid)))
            .getSingleOrNull();
    origin = SongOrigin(
      bankSongUuid: link.targetUuid,
      bankContentHash: link.targetContentHash,
      bankUuid: bankSong?.sourceBank,
    ).toJson();
  }

  return {
    'uuid': song.uuid,
    'title': song.title,
    'lyrics': song.lyrics,
    'lyricsFormat': song.lyricsFormat.value,
    'keyField': const KeyFieldConverter().toSql(song.keyField),
    'contentMap': song.contentMap,
    'checkpoints': song.checkpoints,
    'origin': origin,
  };
}
