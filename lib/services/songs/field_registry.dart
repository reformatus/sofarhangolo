import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/bank/bank.dart';
import '../../services/bank/banks.dart';
import '../../ui/base/songs/widgets/filter/types/bank/state.dart';
import '../../ui/base/songs/widgets/filter/types/field_type.dart';

part 'field_registry.g.dart';

Iterable<Bank> scopedBanksForSongFields(
  Iterable<Bank> banks, {
  required Set<String> bankFilters,
}) {
  if (bankFilters.isEmpty) {
    return banks;
  }

  return banks.where((bank) => bankFilters.contains(bank.uuid));
}

SongFieldCatalog catalogForBank(Bank bank) {
  return SongFieldCatalog.parse(bank.songFields);
}

@Riverpod(keepAlive: true)
Future<SongFieldCatalog> activeSongFieldCatalog(Ref ref) async {
  final bankFilters = ref.watch(banksFilterStateProvider);
  final banks = await ref.watch(watchAllBanksProvider.future);

  return mergeSongFieldCatalogs(
    scopedBanksForSongFields(
      banks,
      bankFilters: bankFilters,
    ).map(catalogForBank),
  );
}
