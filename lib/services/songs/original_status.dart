import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';

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
/// Returns null when [song] is not a copy of another song
/// ([Song.originalSongUuid] is null).
@riverpod
Future<OriginalSongStatus?> originalSongStatus(Ref ref, Song song) async {
  final originalUuid = song.originalSongUuid;
  if (originalUuid == null) {
    return null;
  }

  final original = await (db.songs.select()
        ..where((s) => s.uuid.equals(originalUuid)))
      .getSingleOrNull();

  if (original == null) {
    return OriginalSongStatus.missing;
  }

  return original.stableContentHash == song.originalContentHash
      ? OriginalSongStatus.unchanged
      : OriginalSongStatus.changed;
}
