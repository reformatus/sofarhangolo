import 'package:drift/drift.dart';

@TableIndex(name: 'asset_source_url', columns: {#sourceUrl}, unique: true)
class Assets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songUuid => text()();

  /// Resolved download URL of a bank-cached file. Null for local songs'
  /// attachments, which are found by (songUuid, fieldName) instead. The
  /// unique index below ignores nulls, so any number of local rows coexist.
  TextColumn get sourceUrl => text().nullable()();
  TextColumn get fieldName => text()();
  BlobColumn get content => blob()();
}
