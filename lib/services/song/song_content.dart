import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';

part 'song_content.g.dart';

/// A content-sensitive snapshot of a stored song.
///
/// [Song] equality is uuid-only, and Riverpod dedupes provider states with
/// `==`, so watching a bare [Song] would not notify watchers when only the
/// content changed. Comparing [contentHash] (plus the uuid) makes a snapshot
/// notice content changes, so consumers rebuild.
@immutable
class SongSnapshot {
  const SongSnapshot(this.song, this.contentHash);

  final Song song;
  final String contentHash;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongSnapshot &&
          other.song.uuid == song.uuid &&
          other.contentHash == contentHash;

  @override
  int get hashCode => Object.hash(song.uuid, contentHash);
}

/// The canonical, watching source of a song's content, keyed by uuid.
///
/// Emits whenever the row changes - local edits, attachment writes, bank
/// updates, and (later) remote content sync - so consumers stay live without
/// navigating away and back. Emits null when the song does not exist.
@riverpod
Stream<SongSnapshot?> songContent(Ref ref, String uuid) {
  return (db.select(db.songs)..where((s) => s.uuid.equals(uuid)))
      .watchSingleOrNull()
      .map((song) => song == null ? null : SongSnapshot(song, song.contentHash));
}
