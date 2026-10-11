import 'package:drift/drift.dart';

/// Relationship between two songs. The set of values is append-only:
/// never remove or reorder entries, only add new ones at the end.
enum SongLinkType { localCopyOf }

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
