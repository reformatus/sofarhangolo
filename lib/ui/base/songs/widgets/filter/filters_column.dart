import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../data/song/song_fields.dart';
import '../../../../../services/songs/filter.dart';
import '../../../../common/error/card.dart';
import 'types/bank/bank_filter_card.dart';
import 'types/key/key_filter_card.dart';
import 'types/multiselect-tags/multiselect_filter_card.dart';

/// The filter cards, as a lazy list so a card scrolled out of view is disposed
/// and stops querying. Callers embedding it in another scroll view pass
/// [shrinkWrap] and [physics].
class FiltersColumn extends ConsumerWidget {
  const FiltersColumn({
    this.scrollController,
    this.shrinkWrap = false,
    this.physics,
    this.fadeEdges = false,
    super.key,
  });

  final ScrollController? scrollController;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  /// Wrap the list in a fading-edge scroll view (the wide sidebar does).
  final bool fadeEdges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterableFieldsList = ref.watch(existingFilterableFieldsProvider);

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
        final cards = filterList.reversed.toList();

        final list = ListView.builder(
          controller: scrollController,
          shrinkWrap: shrinkWrap,
          physics: physics,
          itemCount: cards.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return const BankFilterCard();

            final entry = cards[index - 1];
            return switch (entry.value.field.filterUse) {
              SongFieldUse.filterKey => KeyFilterCard(
                fieldPopulatedCount: entry.value.count,
              ),
              SongFieldUse.filterMultiselect => MultiselectFilterCard(
                field: entry.value.field,
                fieldPopulatedCount: entry.value.count,
              ),
              // Unreachable: fields only reach this list through a filter use.
              _ => const SizedBox.shrink(),
            };
          },
        );
        return fadeEdges
            ? FadingEdgeScrollView.fromScrollView(child: list)
            : list;
    }
  }
}
