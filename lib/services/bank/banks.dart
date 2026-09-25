import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/bank/bank.dart';
import '../../data/database.dart';

part 'banks.g.dart';

@Riverpod(keepAlive: true)
Stream<List<Bank>> watchAllBanks(Ref ref) async* {
  yield* dbWatchAllBanks();
}

Stream<List<Bank>> dbWatchAllBanks() async* {
  yield* (db.banks.select().watch());
}

/// Returns the built-in local bank that stores user-created and copied
/// songs. Throws if missing; only a broken migration can cause that.
Future<Bank> localBank() async {
  return await (db.banks.select()
        ..where((b) => b.access.equals(BankAccess.local.index)))
      .getSingle();
}
