import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../../services/key/filter.dart';
import '../../../../../../common/error/card.dart';
import '../../../../../../common/key_text.dart';
import '../../common/filter_chip.dart';
import 'state.dart';

class KeyFilterCard extends ConsumerStatefulWidget {
  const KeyFilterCard({required this.fieldPopulatedCount, super.key});

  final int fieldPopulatedCount;

  @override
  ConsumerState<KeyFilterCard> createState() => _KeyFilterCardState();
}

class _KeyFilterCardState extends ConsumerState<KeyFilterCard> {
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
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                          fontSize: Theme.of(
                            context,
                          ).textTheme.bodySmall!.fontSize,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.keys.isNotEmpty)
                SizedBox(
                  height: 42,
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
        subtitle: Column(
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

  Widget chipsRow(
    AsyncValue<List<KeyFilterSelectable>> selectables, {
    bool modes = false,
  }) {
    return switch (selectables) {
      AsyncError(:final error, :final stackTrace) => LErrorCard.fromError(
        error: error,
        stackTrace: stackTrace,
        title: 'Hiba a hangsoradatok lekérdezésekor',
        icon: Icons.error,
        showReportButton: false,
      ),
      AsyncValue(:final value) => SizedBox(
        height: 42,
        child: value == null
            ? Align(
                alignment: Alignment.center,
                child: LinearProgressIndicator(),
              )
            : FadingEdgeScrollView.fromScrollView(
                child: ListView.builder(
                  // hack, but still better than code repetition...
                  controller: modes
                      ? modesScrollController
                      : pitchesScrollController,
                  shrinkWrap: true,
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, i) => LFilterChip(
                    label: value[i].addingKey
                        ? displayKeyString(value[i].label)
                        : (modes
                            ? displayKeyMode(value[i].label)
                            : displayKeyPitch(value[i].label)),
                    selected: value[i].selected,
                    onSelected: value[i].onSelected,
                    special: value[i].addingKey,
                    leading: value[i].addingKey
                        ? Icon(Icons.add, size: 20)
                        : null,
                  ),
                  itemCount: value.length,
                ),
              ),
      ),
    };
  }
}
