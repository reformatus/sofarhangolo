import 'package:drift/drift.dart';

@TableIndex(name: 'asset_source_url', columns: {#sourceUrl}, unique: true)
class Assets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get songUuid => text()();
  TextColumn get sourceUrl => text()();
  TextColumn get fieldName => text()();
  BlobColumn get content => blob()();
}
