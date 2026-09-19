import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../../services/songs/filter.dart';
import '../../common/async_chip_row_handler.dart';
import '../../common/base_filter_card.dart';
import '../field_type.dart';
import 'state.dart';

class MultiselectFilterCard extends ConsumerWidget {
  const MultiselectFilterCard({
    required this.field,
    required this.fieldType,
    required this.fieldPopulatedCount,
    super.key,
  });

  final String field;
  final FieldType fieldType;
  final int fieldPopulatedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectableValues = ref.watch(
      selectableValuesForFilterableFieldProvider(field, fieldType),
    );
    final filterState = ref.watch(multiselectTagsFilterStateProvider);
    final filterStateNotifier = ref.read(
      multiselectTagsFilterStateProvider.notifier,
    );

    final isActive = filterState.containsKey(field);

    return BaseFilterCard(
      icon: songFieldsMap[field]!['icon'] ?? Icons.filter_list,
      title: songFieldsMap[field]!['title_hu'] ?? "[Szűrő neve hiányzik]",
      isActive: isActive,
      onResetPressed: () => filterStateNotifier.resetFilterField(field),
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
        asyncValue: selectableValues,
        selectedValues: filterState[field]?.toSet(),
        onChipToggle: (item, selected) {
          if (selected) {
            filterStateNotifier.addFilter(field, item);
          } else {
            filterStateNotifier.removeFilter(field, item);
          }
        },
        chipLabelBuilder: (item) => item,
      ),
    );
  }
}
