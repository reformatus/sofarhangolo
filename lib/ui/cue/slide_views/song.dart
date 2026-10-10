import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/cue/slide.dart';
import '../../../data/song/song.dart';
import '../../../services/song/song_content.dart';
import '../../song/lyrics/view.dart';
import '../../song/sheet/view.dart';
import '../../song/state.dart';
import '../session/session_provider.dart';
import 'missing_song.dart';

/// Resolves the current content for [slide]: live DB content once the stream
/// has produced a value, the cached snapshot while it is still loading, or
/// null when the song is missing on this device.
Song? resolveLiveSong(WidgetRef ref, SongSlide slide) {
  final async = ref.watch(songContentProvider(slide.songUuid));
  return async.hasValue ? async.value?.song : slide.song;
}

class SongSlideTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final liveSong = resolveLiveSong(ref, slide);

    return ReorderableDelayedDragStartListener(
      index: index,
      child: MediaQuery.removeViewPadding(
        removeBottom: true,
        removeLeft: true,
        removeRight: true,
        removeTop: true,
        context: context,
        child: liveSong == null
            ? MissingSongTile(
                slide,
                index,
                selectCallback: selectCallback,
                removeCallback: removeCallback,
                isCurrent: isCurrent,
              )
            : ListTile(
                title: Text(liveSong.title),
                onTap: selectCallback,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: removeCallback,
                      icon: const Icon(Icons.delete_outline),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
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
  const SongSlideView(
    this.songSlide,
    this.cueId, {
    this.enableTextActions = true,
    super.key,
  });

  final SongSlide songSlide;
  final String? cueId;

  /// Whether lyrics slides install the text actions (menu, selection dialog,
  /// hover highlight).
  final bool enableTextActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSlide = switch (ref
        .watch(slideSnapshotProvider(songSlide.uuid))
        .slide) {
      SongSlide currentSlide => currentSlide,
      _ => songSlide,
    };

    final liveSong = resolveLiveSong(ref, currentSlide);
    if (liveSong == null) {
      return MissingSongView(songSlide: currentSlide);
    }

    return switch (currentSlide.viewType) {
      SongViewType.svg => SheetView.svg(liveSong),
      SongViewType.pdf => SheetView.pdf(liveSong),
      SongViewType.lyrics || SongViewType.chords => LyricsView(
        liveSong,
        songSlide: currentSlide,
        forceSingleColumnLayout: true,
        textActionsEnabled: enableTextActions,
      ),
    };
  }
}
