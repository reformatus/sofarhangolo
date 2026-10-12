import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../../data/bank/bank.dart';
import '../../../../../../../services/bank/banks.dart';
import '../../../../../../../services/songs/facet.dart';
import '../../common/async_chip_row_handler.dart';
import '../../common/base_filter_card.dart';
import 'state.dart';

class BankFilterCard extends ConsumerStatefulWidget {
  const BankFilterCard({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _BankFilterCardState();
}

class _BankFilterCardState extends ConsumerState<BankFilterCard> {
  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(watchAllBanksProvider);
    final bankUuids = ref.watch(banksFilterStateProvider);
    final available = ref.watch(bankFacetProvider);

    // Only the banks the current query can still reach, plus the selected ones.
    List<Bank> selectable(Set<String> uuids) => [
      for (final bank in banks.requireValue)
        if (uuids.contains(bank.uuid) || bankUuids.contains(bank.uuid)) bank,
    ];

    final asyncBanks = banks.hasValue ? available.whenData(selectable) : banks;

    // Nothing to offer and nothing selected: the card has no purpose. Reads
    // `available.value` rather than [asyncBanks] so a facet that is still
    // loading keeps the card hidden instead of flashing it back in (see
    // [MultiselectFilterCard]).
    final reachable = available.value;
    if (banks.hasValue && reachable != null && selectable(reachable).isEmpty) {
      return const SizedBox.shrink();
    }

    return BaseFilterCard(
      icon: Icons.library_music,
      title: 'Daltár',
      isActive: bankUuids.isNotEmpty,
      onResetPressed: () => ref.read(banksFilterStateProvider.notifier).reset(),
      child: AsyncChipRowHandlerOf<Bank>(
        asyncValue: asyncBanks,
        selectedValues: banks.hasValue
            ? banks.requireValue
                  .where((b) => bankUuids.contains(b.uuid))
                  .toSet()
            : {},
        onChipToggle: (bank, setTo) => ref
            .read(banksFilterStateProvider.notifier)
            .setFilter(bank.uuid, setTo),
        chipLabelBuilder: (bank) => bank.name,
        chipLeadingBuilder: (bank) => (bank.tinyLogo != null)
            ? SizedBox.square(
                dimension: 20,
                child: Image.memory(bank.tinyLogo!),
              )
            : null,
      ),
    );
  }
}
