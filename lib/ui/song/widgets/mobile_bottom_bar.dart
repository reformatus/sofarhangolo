import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/song/song.dart';
import '../add_to_cue_search.dart';
import '../song_cue_actions.dart';
import '../state.dart';
import '../transpose/state.dart';
import '../transpose/widget.dart';
import '../view_chooser.dart';
import 'report_song_button.dart';
import 'transpose_overlay_button.dart';

class MobileBottomBar extends ConsumerWidget {
  const MobileBottomBar({
    super.key,
    required this.song,
    required this.constraints,
    required this.actionButtonsScrollController,
    required this.transposeOverlayVisible,
    this.showOpenCueAction = false,
  });

  final Song song;
  final BoxConstraints constraints;
  final ScrollController actionButtonsScrollController;
  final ValueNotifier<bool> transposeOverlayVisible;
  final bool showOpenCueAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewTypeAsync = ref.watch(viewTypeForProvider(song, null));
    if (!viewTypeAsync.hasValue) return SizedBox.shrink();
    final viewType = viewTypeAsync.requireValue;

    final transpose = ref.watch(transposeStateForProvider(song));

    return SizedBox(
      height: 50,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ViewChooser(
              song: song,
              songSlide: null,
              useDropdown: constraints.maxWidth < 550,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FadingEdgeScrollView.fromScrollView(
                    child: ListView(
                      controller: actionButtonsScrollController,
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      shrinkWrap: true,
                      children: _buildActionButtons(
                        viewType,
                        transpose,
                        ref,
                      ).reversed.toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(
    SongViewType viewType,
    dynamic transpose,
    WidgetRef ref,
  ) {
    return [
      ReportSongButton(song),
      AddToCueSearch(
        song: song,
        isDesktop: false,
        viewType: viewType,
        transpose: transpose,
      ),
      if (showOpenCueAction)
        OpenCueActionControl(
          song: song,
          transpose: transpose,
        ),
      if (viewType == SongViewType.chords) ...[
        const VerticalDivider(),
        TransposeResetButton(song, songSlide: null, isCompact: false),
        TransposeOverlayButton(
          song: song,
          transpose: transpose,
          overlayVisible: transposeOverlayVisible,
        ),
      ],
    ];
  }
}
