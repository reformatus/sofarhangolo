import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../../services/key/filter.dart';
import '../../../../../../../services/songs/facet.dart';
import '../../../../../../common/error/card.dart';
import '../../../../../../common/key_text.dart';
import '../../common/empty_chip_row.dart';
import '../../common/filter_chip.dart';
import '../../common/skeleton_chip_row.dart';
import 'state.dart';

class KeyFilterCard extends ConsumerStatefulWidget {
  const KeyFilterCard({required this.fieldPopulatedCount, super.key});

  final int fieldPopulatedCount;

  @override
  ConsumerState<KeyFilterCard> createState() => _KeyFilterCardState();
}

class _KeyFilterCardState extends ConsumerState<KeyFilterCard> {
  /// A chip row's height; the card shows two of them (pitches, modes).
  static const _chipRowHeight = 42.0;

  @override
  void initState() {
    // init scroll controllers in advance so that fading edge scroll view doesn't lose them on rebuild
    keysScrollController = ScrollController();
    pitchesScrollController = ScrollController();
    modesScrollController = ScrollController();
    super.initState();
  }

  late final ScrollController keysScrollController;
  late final ScrollController pitchesScrollController;
  late final ScrollController modesScrollController;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(keyFilterStateProvider);
    final isActive =
        !(state.pitches.isEmpty && state.modes.isEmpty && state.keys.isEmpty);

    final selectablePitches = ref.watch(selectablePitchesProvider);
    final selectableModes = ref.watch(selectableModesProvider);

    // No key in the collection matches the current query and none is selected:
    // the rows have nothing to offer. Read the value, which survives a reload,
    // so the line does not flash back to a skeleton.
    final availableKeys = ref.watch(keyFacetProvider).value;
    final noReachableKeys =
        !isActive && availableKeys != null && availableKeys.keys.isEmpty;

    return Card(
      elevation: isActive ? 3 : 0,
      color: isActive ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: !isActive
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.piano),
              )
            : SizedBox(
                width: 32,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      ref.read(keyFilterStateProvider.notifier).reset(),
                  icon: Icon(Icons.clear),
                ),
              ),

        title: AnimatedSize(
          duration: Durations.medium1,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              AnimatedOpacity(
                duration: Durations.medium1,
                opacity: state.keys.isEmpty ? 1 : 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Hangnem'),
                    Expanded(
                      child: Text(
                        "  ${widget.fieldPopulatedCount} dalnál megadva",
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                          fontSize: Theme.of(context)
                              .textTheme
                              .bodySmall!
                              .fontSize,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.keys.isNotEmpty)
                SizedBox(
                  height: _chipRowHeight,
                  child: FadingEdgeScrollView.fromScrollView(
                    child: ListView(
                      controller: keysScrollController,
                      scrollDirection: Axis.horizontal,
                      children: state.keys
                          .map(
                            (e) => LFilterChip(
                              label: displayKeyField(e),
                              onSelected: (v) => ref
                                  .read(keyFilterStateProvider.notifier)
                                  .setKeyTo(e, v),
                              selected: state.keys.contains(e),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
        subtitle: noReachableKeys
            ? const EmptyChipRow(height: _chipRowHeight * 2)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  chipsRow(selectablePitches),
                  chipsRow(selectableModes, modes: true),
                ],
              ),
      ),
    );
  }

  /// The last values each row had, kept while a refresh is in flight so the row
  /// fades its chips instead of flashing a placeholder.
  List<KeyFilterSelectable>? _lastPitches;
  List<KeyFilterSelectable>? _lastModes;

  Widget chipsRow(
    AsyncValue<List<KeyFilterSelectable>> selectables, {
    bool modes = false,
  }) {
    if (selectables.hasValue) {
      if (modes) {
        _lastModes = selectables.requireValue;
      } else {
        _lastPitches = selectables.requireValue;
      }
    }
    final values = selectables.value ?? (modes ? _lastModes : _lastPitches);

    if (values == null) {
      return switch (selectables) {
        AsyncError(:final error, :final stackTrace) => LErrorCard.fromError(
          error: error,
          stackTrace: stackTrace,
          title: 'Hiba a hangsoradatok lekérdezésekor',
          icon: Icons.error,
          showReportButton: false,
        ),
        _ => const SkeletonChipRow(),
      };
    }

    return SizedBox(
      height: _chipRowHeight,
      child: AnimatedOpacity(
        duration: Durations.short4,
        opacity: selectables.isLoading ? 0.45 : 1,
        child: FadingEdgeScrollView.fromScrollView(
          child: ListView.builder(
            // hack, but still better than code repetition...
            controller: modes ? modesScrollController : pitchesScrollController,
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, i) => LFilterChip(
              label: values[i].addingKey
                  ? displayKeyString(values[i].label)
                  : (modes
                        ? displayKeyMode(values[i].label)
                        : displayKeyPitch(values[i].label)),
              selected: values[i].selected,
              onSelected: values[i].onSelected,
              special: values[i].addingKey,
              leading: values[i].addingKey ? Icon(Icons.add, size: 20) : null,
            ),
            itemCount: values.length,
          ),
        ),
      ),
    );
  }
}
