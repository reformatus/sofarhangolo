import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/bank/bank.dart';
import '../../data/database.dart';
import '../../data/log/logger.dart';

part 'bank_updated.g.dart';

Future setAsUpdatedNow(Bank bank) {
  return (db.banks.update()..where((b) => b.id.equals(bank.id))).write(
    BanksCompanion(lastUpdated: Value(DateTime.now())),
  );
}

/// Checks if there was ever a successful bank update.\
/// Effectively, checks if the app has been launched for the first time.
@Riverpod(keepAlive: true)
Future<bool> hasEverUpdatedAnything(Ref ref) async {
  try {
    return (await (db.banks.select()..where((b) => b.lastUpdated.isNotNull()))
            .get())
        .isNotEmpty;
  } catch (e, s) {
    log.severe('Hiba történt a tárak legutóbbi frissítésének betöltésekor', e, s);
    return false;
  }
}
