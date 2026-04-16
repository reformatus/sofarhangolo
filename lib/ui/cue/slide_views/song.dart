import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/cue/slide.dart';
import '../../song/lyrics/view.dart';
import '../../song/sheet/view.dart';
import '../../song/state.dart';
import '../session/session_provider.dart';

class SongSlideTile extends StatelessWidget {
  const SongSlideTile(
    this.slide,
    this.index, {
    required this.selectCallback,
    required this.removeCallback,
    required this.isCurrent,
    super.key,
  });

  final GestureTapCallback selectCallback;
  final GestureTapCallback removeCallback;
  final bool isCurrent;
  final SongSlide slide;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ReorderableDelayedDragStartListener(
      index: index,
      child: MediaQuery.removeViewPadding(
        removeBottom: true,
        removeLeft: true,
        removeRight: true,
        removeTop: true,
        context: context,
        child: ListTile(
          title: Text(slide.song.title),
          onTap: selectCallback,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: removeCallback,
                icon: Icon(Icons.delete_outline),
              ),
              ReorderableDragStartListener(
                index: index,
                child: Icon(Icons.drag_handle),
              ),
            ],
          ),
          selected: isCurrent,
          selectedTileColor: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }
}

class SongSlideView extends ConsumerWidget {
  const SongSlideView(this.songSlide, this.cueId, {super.key});

  final SongSlide songSlide;
  final String? cueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSlide = switch (ref
        .watch(slideSnapshotProvider(songSlide.uuid))
        .slide) {
      SongSlide currentSlide => currentSlide,
      _ => songSlide,
    };

    return switch (currentSlide.viewType) {
      SongViewType.svg => SheetView.svg(currentSlide.song),
      SongViewType.pdf => SheetView.pdf(currentSlide.song),
      SongViewType.lyrics || SongViewType.chords => LyricsView(
        currentSlide.song,
        songSlide: currentSlide,
        forceSingleColumnLayout: true,
      ),
    };
  }
}
