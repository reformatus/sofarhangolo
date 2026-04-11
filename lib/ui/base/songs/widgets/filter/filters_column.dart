import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../services/songs/filter.dart';
import '../../../../common/error/card.dart';
import 'types/bank/bank_filter_card.dart';
import 'types/field_type.dart';
import 'types/key/key_filter_card.dart';
import 'types/multiselect-tags/multiselect_filter_card.dart';

class FiltersColumn extends ConsumerWidget {
  const FiltersColumn({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var filterableFieldsList = ref.watch(existingFilterableFieldsProvider);

    switch (filterableFieldsList) {
      case AsyncError(:final error, :final stackTrace):
        return LErrorCard.fromError(
          error: error,
          stackTrace: stackTrace,
          title: 'Hiba a szűrők betöltése közben',
          icon: Icons.error,
        );
      case AsyncValue(:final value):
        if (value == null) return Center(child: LinearProgressIndicator());

        var filterList = value.entries.toList();
        filterList.sort((a, b) => a.value.count.compareTo(b.value.count));

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BankFilterCard(),
            ...filterList.reversed.map(
              (e) => switch (e.value.type) {
                FieldType.multiselect ||
                FieldType.multiselectTags => MultiselectFilterCard(
                  field: e.key,
                  fieldType: e.value.type,
                  fieldPopulatedCount: e.value.count,
                ),
                FieldType.key => KeyFilterCard(
                  fieldPopulatedCount: e.value.count,
                ),
                _ => LErrorCard(
                  type: LErrorType.warning,
                  title: 'Nem támogatott szűrőtípus!',
                  message: e.value.toString(),
                  icon: Icons.filter_alt,
                ),
              },
            ),
          ],
        );
    }
  }
}
