import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../../data/song/song_fields.dart';
import '../../../../../../../services/songs/facet.dart';
import '../../common/async_chip_row_handler.dart';
import '../../common/base_filter_card.dart';
import 'state.dart';

class MultiselectFilterCard extends ConsumerWidget {
  const MultiselectFilterCard({
    required this.field,
    required this.fieldPopulatedCount,
    super.key,
  });

  final SongField field;
  final int fieldPopulatedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiName = field.apiName;
    final available = ref.watch(fieldFacetProvider(apiName));
    final filterState = ref.watch(multiselectTagsFilterStateProvider);
    final filterStateNotifier = ref.read(
      multiselectTagsFilterStateProvider.notifier,
    );

    final selected = filterState[apiName]?.toSet() ?? const <String>{};
    final isActive = filterState.containsKey(apiName);

    // The values the current query can still reach, plus the selected ones so
    // they stay deselectable.
    List<String> selectable(Set<String> values) =>
        {...values, ...selected}.toList()..sort();

    final asyncValues = available.whenData(selectable);

    // Nothing to offer and nothing selected: the card has no purpose.
    //
    // This reads `available.value`, not [asyncValues]: while a new query is in
    // flight `whenData` yields a value-less AsyncLoading, so a card that had
    // already hidden itself would pop back into view for the length of the
    // debounce and vanish again on the empty result. `value` carries the
    // previous set across the reload, so the card only returns once a query
    // actually reaches something.
    final reachable = available.value;
    if (reachable != null && selectable(reachable).isEmpty) {
      return const SizedBox.shrink();
    }

    return BaseFilterCard(
      icon: field.icon ?? Icons.filter_list,
      title: field.title,
      isActive: isActive,
      onResetPressed: () => filterStateNotifier.resetFilterField(apiName),
      trailing: Text(
        "  $fieldPopulatedCount dalnál megadva",
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.end,
        overflow: TextOverflow.fade,
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
          fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
        ),
      ),
      child: AsyncChipRowHandlerOf<String>(
        asyncValue: asyncValues,
        selectedValues: selected,
        onChipToggle: (item, isSelected) {
          if (isSelected) {
            filterStateNotifier.addFilter(apiName, item);
          } else {
            filterStateNotifier.removeFilter(apiName, item);
          }
        },
        chipLabelBuilder: (item) => item,
      ),
    );
  }
}
