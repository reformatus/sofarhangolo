import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../common/error/card.dart';
import 'filter_chip.dart';
import 'skeleton_chip_row.dart';

/// A reusable widget that displays an async list of values as horizontal filter chips
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
    return switch (widget.asyncValue) {
      AsyncError(:final error, :final stackTrace) => LErrorCard.fromError(
        error: error,
        stackTrace: stackTrace,
        title: 'Hiba a szűrőértékek lekérdezése közben',
        icon: Icons.warning,
        showReportButton: true,
      ),
      AsyncValue(:final value) =>
        value == null
            ? SkeletonChipRow(height: widget.height)
            : SizedBox(
                height: widget.height,
                child: FadingEdgeScrollView.fromScrollView(
                  child: ListView.builder(
                    shrinkWrap: true,
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    itemCount: value.length,
                    itemBuilder: (context, i) {
                      final item = value[i];
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
    };
  }
}
