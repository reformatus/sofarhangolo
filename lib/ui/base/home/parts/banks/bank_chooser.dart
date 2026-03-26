import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../data/bank/bank.dart';
import '../../../../../services/bank/banks.dart';
import '../../../../../services/songs/update.dart';
import '../../../../common/error/card.dart';
import '../../../../common/hero_dialog_route.dart';
import '../../../../loading/banner.dart';
import '../../../songs/widgets/filter/types/bank/state.dart';
import 'details_dialog.dart';

class BankChooser extends ConsumerWidget {
  const BankChooser({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var banks = ref.watch(watchAllBanksProvider);
    return switch (banks) {
      AsyncError(:final error, :final stackTrace) => LErrorCard(
        type: LErrorType.error,
        title: 'Nem sikerült betölteni a daltárakat',
        icon: Icons.error,
        message: error.toString(),
        stack: stackTrace.toString(),
      ),
      AsyncLoading() => Center(child: CircularProgressIndicator()),
      AsyncValue<List<Bank>>(:final value!) => Column(
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 18,
                ),
                child: Text(
                  'DALTÁRAK',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                icon: Icon(Icons.cloud_sync_outlined),
                tooltip: 'Frissítés most',
                onPressed: () {
                  unawaited(
                    ref
                        .read(bankSongUpdateSchedulerProvider.notifier)
                        .refreshAllEnabledBanks(),
                  );
                  showOnlineBanksUpdatingBanner();
                },
              ),
              /*IconButton(
                icon: Icon(Icons.settings_outlined),
                onPressed: () {},
              ),*/
              Spacer(),
              Padding(
                padding: EdgeInsets.only(right: 6),
                child: FilledButton.icon(
                  iconAlignment: IconAlignment.end,
                  onPressed: () => context.push('/bank'),
                  label: Text('Összes dal'),
                  icon: Icon(Icons.chevron_right),
                ),
              ),
            ],
          ),
          ...value.map((bank) => BankTile(bank)),
        ],
      ),
    };
  }
}

class BankTile extends ConsumerWidget {
  const BankTile(this.bank, {super.key});

  final Bank bank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Hero(
      tag: 'details-${bank.uuid}',
      child: Card(
        margin: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: InkWell(
          onTap: () => showHeroDialog(
            context: context,
            builder: (context) => BankDetailsDialog(bank),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: 10, top: 10, bottom: 10),
                  child: SizedBox.square(
                    dimension: 54,
                    child: FittedBox(
                      child: bank.logo != null
                          ? Image.memory(bank.logo!)
                          : Icon(Icons.library_music),
                    ),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: Text(
                      bank.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                    ),
                    subtitle:
                        bank.description != null && bank.description!.isNotEmpty
                        ? Text(
                            bank.description!,
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    /*trailing: Row( // TODO download functionality
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.download_for_offline_outlined),
                          onPressed: () {},
                        ),
                      ],
                    ),*/
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Material(
                    elevation: 5,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: InkWell(
                      onTap: () {
                        ref
                            .read(banksFilterStateProvider.notifier)
                            .setFilter(bank.uuid, true, clearOthers: true);
                        context.push('/bank');
                      },
                      child: Center(
                        child: Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
