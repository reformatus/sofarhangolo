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

/// Watches the [SongLinkType.localCopyOf] link of [song] joined with the
/// linked original song's row.
///
/// Watching the join (both tables) keeps the derived providers live: adding or
/// removing a link, a bank update to the original, or the original's deletion
/// all re-emit.
JoinedSelectStatement _originalJoin(Song song) {
  final link = db.songLinks;
  final original = db.songs;
  return db.select(link).join([
    leftOuterJoin(original, original.uuid.equalsExp(link.targetUuid)),
  ])..where(
    link.sourceUuid.equals(song.uuid) &
        link.type.equals(SongLinkType.localCopyOf.index),
  );
}

/// Tracks whether the bank original of a local song copy changed or vanished.
///
/// Returns null when [song] has no [SongLinkType.localCopyOf] link.
@riverpod
Stream<OriginalSongStatus?> originalSongStatus(Ref ref, Song song) {
  final link = db.songLinks;
  final original = db.songs;

  return _originalJoin(song).watch().map((rows) {
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final originalRow = row.readTableOrNull(original);
    if (originalRow == null) {
      return OriginalSongStatus.missing;
    }

    return originalRow.contentHash == row.readTable(link).targetContentHash
        ? OriginalSongStatus.unchanged
        : OriginalSongStatus.changed;
  });
}

/// The bank song a local copy was made from, or null when there is no
/// [SongLinkType.localCopyOf] link or the original no longer exists.
@riverpod
Stream<Song?> originalSong(Ref ref, Song song) {
  final original = db.songs;

  return _originalJoin(song).watch().map((rows) {
    if (rows.isEmpty) {
      return null;
    }
    return rows.first.readTableOrNull(original);
  });
}
