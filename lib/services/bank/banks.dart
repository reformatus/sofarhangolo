import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/bank/bank.dart';
import '../../data/database.dart';

part 'banks.g.dart';

@Riverpod(keepAlive: true)
Stream<List<Bank>> watchAllBanks(Ref ref) async* {
  yield* dbWatchAllBanks();
}

/// Looks up a bank by uuid. Null while banks are still loading, when the
/// uuid matches no bank, or when the uuid is null (local songs have no
/// source bank).
@Riverpod(keepAlive: true)
Bank? bankByUuid(Ref ref, String? uuid) {
  if (uuid == null) return null;
  final banks = ref.watch(watchAllBanksProvider).value ?? [];
  return banks.where((b) => b.uuid == uuid).firstOrNull;
}

Stream<List<Bank>> dbWatchAllBanks() async* {
  yield* (db.banks.select().watch());
}
