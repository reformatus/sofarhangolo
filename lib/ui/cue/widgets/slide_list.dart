import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/cue/slide.dart';
import '../../common/centered_hint.dart';
import '../../common/confirm_dialog.dart';
import '../session/session_provider.dart';
import '../slide_views/song.dart';
import '../slide_views/unknown.dart';

/// A drawer or side panel that displays a list of slides for a cue
/// Uses the current slide from state management instead of an index
class SlideList extends ConsumerWidget {
  const SlideList({this.onSlideSelected, super.key});

  final ValueChanged<Slide>? onSlideSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSlideUuid = ref.watch(currentSlideUuidProvider);
    final slideUuids = ref.watch(slideDeckProvider).slideUuids;

    if (slideUuids.isEmpty) return CenteredHint('Üres lista');

    return ReorderableListView.builder(
      itemCount: slideUuids.length,
      buildDefaultDragHandles: false,
      onReorder: (int from, int to) {
        ref.read(activeCueSessionProvider.notifier).reorderSlides(from, to);
      },
      itemBuilder: (context, index) {
        final slideUuid = slideUuids[index];
        final slide = ref.watch(slideSnapshotProvider(slideUuid)).slide;

        if (slide == null) {
          return SizedBox(key: ValueKey('missing-slide-$slideUuid'));
        }

        return switch (slide) {
          SongSlide songSlide => SongSlideTile(
            songSlide,
            index,
            key: ValueKey(songSlide.uuid),
            selectCallback: () => _handleSlideSelection(ref, slide),
            removeCallback: () => showConfirmDialog(
              context,
              title: '${songSlide.song.title} - biztos eltávolítod a listából?',
              actionIcon: Icons.delete_outline,
              actionLabel: 'Eltávolítás',
              actionOnPressed: () async {
                ref
                    .read(activeCueSessionProvider.notifier)
                    .removeSlide(slide.uuid);
              },
            ),
            isCurrent: currentSlideUuid == slide.uuid,
          ),
          UnknownTypeSlide unknownSlide => UnknownTypeSlideTile(
            unknownSlide,
            index,
            key: ValueKey(unknownSlide.uuid),
            selectCallback: () => _handleSlideSelection(ref, slide),
            removeCallback: () => ref
                .read(activeCueSessionProvider.notifier)
                .removeSlide(slide.uuid),
            isCurrent: currentSlideUuid == slide.uuid,
          ),
        };
      },
    );
  }

  void _handleSlideSelection(WidgetRef ref, Slide slide) {
    final onSlideSelected = this.onSlideSelected;
    if (onSlideSelected != null) {
      onSlideSelected(slide);
      return;
    }

    ref.read(activeCueSessionProvider.notifier).goToSlide(slide.uuid);
  }
}
