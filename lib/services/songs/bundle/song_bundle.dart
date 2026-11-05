import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../data/song/lyrics/format.dart';
import '../../../data/song/song.dart';
import '../../assets/pick_asset.dart';
import '../../assets/write_song_asset.dart';

/// File extension (without the dot) of song bundle files.
const String songBundleExtension = 'sofar';

/// Value of the manifest's `format` key.
const String songBundleFormat = 'sofarhangolo.songs';

/// Newest bundle version this app writes and understands.
const int songBundleVersion = 1;

const String _manifestName = 'manifest.json';
const String _assetPrefix = 'assets/';

String songBundleAssetPath(String md5) => '$_assetPrefix$md5';

/// A file name for a bundle holding songs/a cue titled [title].
String songBundleFileName(String title) {
  final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return '${safe.isEmpty ? 'dalok' : safe}.$songBundleExtension';
}

/// Why a bundle could not be read.
sealed class SongBundleException implements Exception {
  final String message;
  const SongBundleException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Not a zip, or the manifest/an entry is missing or has the wrong shape.
class MalformedBundle extends SongBundleException {
  const MalformedBundle(super.message);
}

/// A valid manifest whose `format` is not [songBundleFormat].
class UnknownBundleFormat extends SongBundleException {
  final Object? format;
  UnknownBundleFormat(this.format) : super('Unknown bundle format: $format');
}

/// The bundle was written by a newer app: the user should update.
class UnsupportedBundleVersion extends SongBundleException {
  final int version;
  final int supported;
  UnsupportedBundleVersion(this.version, this.supported)
    : super('Bundle version $version is newer than supported $supported');
}

/// Where a bundled local song came from in a bank: the `localCopyOf` link.
class SongOrigin {
  final String bankSongUuid;
  final String? bankContentHash;
  final String? bankUuid;

  const SongOrigin({
    required this.bankSongUuid,
    this.bankContentHash,
    this.bankUuid,
  });

  Map<String, Object?> toJson() => {
    'bankSongUuid': bankSongUuid,
    'bankContentHash': bankContentHash,
    'bankUuid': bankUuid,
  };
}

/// A report of an attachment that was dropped while reading a bundle.
class DroppedAttachment {
  final String songUuid;
  final String field;
  final String reason;

  const DroppedAttachment(this.songUuid, this.field, this.reason);
}

/// One verified song of a bundle. [song] has no sourceBank; its contentMap
/// only holds attachment values whose bytes were verified (in [assets]).
class BundledSong {
  final Song song;
  final SongOrigin? origin;

  /// Verified attachment bytes by field name (`svg`, `pdf`).
  final Map<String, Uint8List> assets;

  final String contentHash;

  BundledSong({required this.song, required this.origin, required this.assets})
    : contentHash = song.contentHash;

  String get uuid => song.uuid;
}

/// A read, verified bundle.
class SongBundle {
  final List<BundledSong> songs;

  /// The cue as `Cue.toJson()` produced it, or null.
  final Map<String, dynamic>? cue;
  final List<DroppedAttachment> droppedAttachments;

  const SongBundle(this.songs, this.cue, this.droppedAttachments);
}

/// Serialises a bundle. [songJson] entries must already be in manifest shape.
Uint8List writeSongBundle({
  required List<Map<String, Object?>> songJson,
  required Map<String, Uint8List> assetsByMd5,
  Map<String, dynamic>? cue,
}) {
  final archive = Archive();
  final manifest = utf8.encode(
    jsonEncode({
      'format': songBundleFormat,
      'version': songBundleVersion,
      'songs': songJson,
      'cue': cue,
    }),
  );
  archive.addFile(ArchiveFile.bytes(_manifestName, manifest));
  for (final entry in assetsByMd5.entries) {
    archive.addFile(
      ArchiveFile.bytes(songBundleAssetPath(entry.key), entry.value),
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Reads and verifies [bytes]. Throws a [SongBundleException]. An attachment
/// that is missing or whose md5 differs from its name/reference is dropped
/// from its song (and listed in the result) instead of failing the read.
SongBundle readSongBundle(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw MalformedBundle('Not a zip archive: $e');
  }

  final manifestFile = archive.findFile(_manifestName);
  if (manifestFile == null) throw const MalformedBundle('No manifest.json');

  final Object? manifest;
  try {
    manifest = jsonDecode(
      utf8.decode(manifestFile.readBytes() ?? Uint8List(0)),
    );
  } catch (e) {
    throw MalformedBundle('Unreadable manifest: $e');
  }
  if (manifest is! Map) {
    throw const MalformedBundle('Manifest is not an object');
  }
  if (manifest['format'] != songBundleFormat) {
    throw UnknownBundleFormat(manifest['format']);
  }
  final version = manifest['version'];
  if (version is! int) throw const MalformedBundle('Missing bundle version');
  if (version > songBundleVersion) {
    throw UnsupportedBundleVersion(version, songBundleVersion);
  }
  if (version < 1) throw const MalformedBundle('Invalid bundle version');

  final rawSongs = manifest['songs'];
  if (rawSongs is! List) throw const MalformedBundle('No songs list');
  final rawCue = manifest['cue'];
  if (rawCue != null && rawCue is! Map) {
    throw const MalformedBundle('Cue is not an object');
  }

  Map<String, dynamic>? cue;
  if (rawCue != null) {
    cue = Map<String, dynamic>.from(rawCue as Map);
    if (cue['uuid'] is! String ||
        cue['title'] is! String ||
        cue['content'] is! List ||
        (cue['content'] as List).any((e) => e is! Map)) {
      throw const MalformedBundle('Invalid cue');
    }
    cue['description'] ??= '';
    cue['cueVersion'] ??= 1;
  }

  // md5 -> bytes of attachments whose content matches their name.
  final verified = <String, Uint8List>{};
  for (final file in archive.files) {
    if (!file.isFile || !file.name.startsWith(_assetPrefix)) continue;
    final name = file.name.substring(_assetPrefix.length);
    final content = file.readBytes();
    if (content != null && localAssetHash(content) == name) {
      verified[name] = content;
    }
  }

  final dropped = <DroppedAttachment>[];
  final songs = <BundledSong>[];
  final seen = <String>{};
  for (final raw in rawSongs) {
    final song = _parseSong(raw, verified, dropped);
    if (!seen.add(song.uuid)) {
      throw MalformedBundle('Duplicate song ${song.uuid}');
    }
    songs.add(song);
  }

  return SongBundle(songs, cue, dropped);
}

T _typed<T>(Map map, String key) {
  final v = map[key];
  if (v is! T) throw MalformedBundle('Song field "$key" is missing or invalid');
  return v;
}

BundledSong _parseSong(
  Object? raw,
  Map<String, Uint8List> verified,
  List<DroppedAttachment> dropped,
) {
  if (raw is! Map) throw const MalformedBundle('Song entry is not an object');
  final uuid = _typed<String>(raw, 'uuid');
  if (uuid.isEmpty) throw const MalformedBundle('Empty song uuid');

  final contentMap = <String, Object>{};
  final assets = <String, Uint8List>{};
  final rawMap = _typed<Map>(raw, 'contentMap');
  for (final e in rawMap.entries) {
    final key = e.key;
    final value = e.value;
    if (key is! String || value == null) {
      throw const MalformedBundle('Invalid contentMap');
    }
    if (assetFieldExtensions.containsKey(key)) {
      final bytes = value is String ? verified[value] : null;
      if (bytes == null) {
        dropped.add(
          DroppedAttachment(uuid, key, 'missing or corrupted attachment'),
        );
      } else {
        contentMap[key] = value as String;
        assets[key] = bytes;
      }
    } else if (value is List) {
      contentMap[key] = value.map((i) => i.toString()).toList();
    } else if (value is String) {
      contentMap[key] = value;
    } else {
      throw const MalformedBundle('Invalid contentMap value');
    }
  }

  final List<KeyField> keys;
  try {
    keys = const KeyFieldConverter().fromSql(_typed<String>(raw, 'keyField'));
  } on SongBundleException {
    rethrow;
  } catch (_) {
    throw const MalformedBundle('Invalid keyField');
  }

  final checkpoints = _typed<List>(raw, 'checkpoints');
  final originRaw = raw['origin'];
  SongOrigin? origin;
  if (originRaw != null) {
    if (originRaw is! Map || originRaw['bankSongUuid'] is! String) {
      throw const MalformedBundle('Invalid origin');
    }
    origin = SongOrigin(
      bankSongUuid: originRaw['bankSongUuid'] as String,
      bankContentHash: originRaw['bankContentHash'] as String?,
      bankUuid: originRaw['bankUuid'] as String?,
    );
  }

  final lyrics = raw['lyrics'];
  if (lyrics != null && lyrics is! String) {
    throw const MalformedBundle('Invalid lyrics');
  }

  return BundledSong(
    song: Song(
      uuid: uuid,
      title: _typed<String>(raw, 'title'),
      lyrics: lyrics as String?,
      lyricsFormat: LyricsFormat.fromString(raw['lyricsFormat'] as String?),
      keyField: keys,
      contentMap: contentMap,
      checkpoints: checkpoints.map((c) => c.toString()).toList(),
    ),
    origin: origin,
    assets: assets,
  );
}
