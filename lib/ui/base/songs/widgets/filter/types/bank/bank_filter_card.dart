import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../../data/bank/bank.dart';
import '../../../../../../../services/bank/banks.dart';
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

    return BaseFilterCard(
      icon: Icons.library_music,
      title: 'Daltár',
      isActive: bankUuids.isNotEmpty,
      onResetPressed: () => ref.read(banksFilterStateProvider.notifier).reset(),
      child: AsyncChipRowHandlerOf<Bank>(
        asyncValue: banks,
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
