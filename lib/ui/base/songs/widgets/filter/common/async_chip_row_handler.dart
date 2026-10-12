import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../common/error/card.dart';
import 'empty_chip_row.dart';
import 'filter_chip.dart';
import 'skeleton_chip_row.dart';

/// An async list of values as horizontal filter chips. A refresh keeps the chips
/// it already has and fades them instead of showing the placeholder.
class AsyncChipRowHandlerOf<T> extends StatefulWidget {
  const AsyncChipRowHandlerOf({
    required this.asyncValue,
    required this.selectedValues,
    required this.onChipToggle,
    required this.chipLabelBuilder,
    this.chipLeadingBuilder,
    this.height = 42,
    super.key,
  });

  /// The async value containing the list of selectable items
  final AsyncValue<List<T>> asyncValue;

  /// The currently selected values
  final Set<T>? selectedValues;

  /// Callback when a chip is toggled
  final void Function(T value, bool selected) onChipToggle;

  /// Function to build the label text for each chip
  final String Function(T value) chipLabelBuilder;

  /// Function to build the leading widget for each chip
  final Widget? Function(T value)? chipLeadingBuilder;

  /// Height of the chip container
  final double height;

  @override
  State<AsyncChipRowHandlerOf<T>> createState() =>
      _AsyncChipRowHandlerOfState<T>();
}

class _AsyncChipRowHandlerOfState<T> extends State<AsyncChipRowHandlerOf<T>> {
  late final ScrollController _scrollController;

  /// The last values we had, kept while a refresh is in flight.
  List<T>? _lastValues;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asyncValue.hasValue) {
      _lastValues = widget.asyncValue.requireValue;
    }
    final values = widget.asyncValue.value ?? _lastValues;

    if (values == null) {
      return switch (widget.asyncValue) {
        AsyncError(:final error, :final stackTrace) => LErrorCard.fromError(
          error: error,
          stackTrace: stackTrace,
          title: 'Hiba a szűrőértékek lekérdezése közben',
          icon: Icons.warning,
          showReportButton: true,
        ),
        _ => SkeletonChipRow(height: widget.height),
      };
    }

    return AnimatedOpacity(
      duration: Durations.short4,
      opacity: widget.asyncValue.isLoading ? 0.45 : 1,
      child: values.isEmpty
          ? EmptyChipRow(height: widget.height)
          : SizedBox(
              height: widget.height,
              child: FadingEdgeScrollView.fromScrollView(
                child: ListView.builder(
                  shrinkWrap: true,
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: values.length,
                  itemBuilder: (context, i) {
                    final item = values[i];
                    final isSelected =
                        widget.selectedValues?.contains(item) ?? false;

                    return LFilterChip(
                      label: widget.chipLabelBuilder(item),
                      leading: (widget.chipLeadingBuilder != null)
                          ? widget.chipLeadingBuilder!(item)
                          : null,
                      onSelected: (newValue) =>
                          widget.onChipToggle(item, newValue),
                      selected: isSelected,
                    );
                  },
                ),
              ),
            ),
    );
  }
}
