import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';
import '../../data/song/song_link.dart';

part 'original_status.g.dart';

/// Relationship between a local song and the bank song it was copied from.
enum OriginalSongStatus {
  /// The original bank song's content matches what the copy was made of.
  unchanged,

  /// The original bank song changed since the local copy was made.
  changed,

  /// The original bank song no longer exists in the database.
  missing,
}

/// Tracks whether the bank original of a local song copy changed or vanished.
///
/// Returns null when [song] has no [SongLinkType.localCopyOf] link.
@riverpod
Future<OriginalSongStatus?> originalSongStatus(Ref ref, Song song) async {
  final link = await (db.songLinks.select()
        ..where(
          (l) =>
              l.sourceUuid.equals(song.uuid) &
              l.type.equals(SongLinkType.localCopyOf.index),
        ))
      .getSingleOrNull();

  if (link == null) {
    return null;
  }

  final original = await (db.songs.select()
        ..where((s) => s.uuid.equals(link.targetUuid)))
      .getSingleOrNull();

  if (original == null) {
    return OriginalSongStatus.missing;
  }

  return original.contentHash == link.targetContentHash
      ? OriginalSongStatus.unchanged
      : OriginalSongStatus.changed;
}
