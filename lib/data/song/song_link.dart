import 'package:drift/drift.dart';

/// Relationship between two songs. The set of values is append-only:
/// never remove or reorder entries, only add new ones at the end.
enum SongLinkType {
  localCopyOf,

  /// A local song created by a file import under a fresh uuid because the
  /// incoming song clashed with one already present; the target is the uuid
  /// the song had in the file (targetContentHash: its hash there).
  importedCopyOf,
}

/// A directed edge from one song to another, e.g. a local copy pointing
/// back to the bank song it was copied from (with the content hash observed
/// at copy time, to detect when the original changed since).
@DataClassName('SongLink')
@TableIndex(name: 'song_links_source', columns: {#sourceUuid})
@TableIndex(name: 'song_links_target', columns: {#targetUuid})
class SongLinks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceUuid => text()();
  IntColumn get type => intEnum<SongLinkType>()();
  TextColumn get targetUuid => text()();
  TextColumn get targetContentHash => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sourceUuid, type, targetUuid},
  ];
}

/// `SongLinks.note` of a [SongLinkType.localCopyOf] link that came from a
/// song file import (not from copying a bank song here): the bank song it
/// points at may never have existed on this device.
const String importedOriginLinkNote = 'imported';
