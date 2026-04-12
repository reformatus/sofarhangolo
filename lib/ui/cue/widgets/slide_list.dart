import 'dart:math' as math;

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
class SlideList extends ConsumerStatefulWidget {
  const SlideList({this.onSlideSelected, this.isVisible = true, super.key});

  final ValueChanged<Slide>? onSlideSelected;
  final bool isVisible;

  @override
  ConsumerState<SlideList> createState() => _SlideListState();
}

class _SlideListState extends ConsumerState<SlideList> {
  static const _scrollDuration = Duration(milliseconds: 300);
  static const _estimatedTileExtent = 72.0;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _tileKeys = {};
  ProviderSubscription<String?>? _currentSlideListener;

  @override
  void initState() {
    super.initState();
    _currentSlideListener = ref.listenManual<String?>(
      currentSlideUuidProvider,
      fireImmediately: false,
      (_, nextSlideUuid) {
        if (nextSlideUuid != null) {
          _scheduleScrollToActiveSlide();
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scheduleScrollToActiveSlide(),
    );
  }

  @override
  void didUpdateWidget(covariant SlideList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isVisible && widget.isVisible) {
      _scheduleScrollToActiveSlide();
    }
  }

  @override
  void dispose() {
    _currentSlideListener?.close();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentSlideUuid = ref.watch(currentSlideUuidProvider);
    final slideUuids = ref.watch(slideDeckProvider).slideUuids;

    if (slideUuids.isEmpty) return CenteredHint('Üres lista');

    return ReorderableListView.builder(
      scrollController: _scrollController,
      itemCount: slideUuids.length,
      buildDefaultDragHandles: false,
      onReorder: (int from, int to) {
        ref.read(activeCueSessionProvider.notifier).reorderSlides(from, to);
        _scheduleScrollToActiveSlide();
      },
      itemBuilder: (context, index) {
        final slideUuid = slideUuids[index];
        final slide = ref.watch(slideSnapshotProvider(slideUuid)).slide;

        if (slide == null) {
          return SizedBox(key: ValueKey('missing-slide-$slideUuid'));
        }

        final tile = switch (slide) {
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

        return KeyedSubtree(key: _tileKeyFor(slideUuid), child: tile);
      },
    );
  }

  GlobalKey _tileKeyFor(String slideUuid) {
    return _tileKeys.putIfAbsent(slideUuid, GlobalKey.new);
  }

  void _handleSlideSelection(WidgetRef ref, Slide slide) {
    final onSlideSelected = widget.onSlideSelected;
    if (onSlideSelected != null) {
      onSlideSelected(slide);
      return;
    }

    ref.read(activeCueSessionProvider.notifier).goToSlide(slide.uuid);
  }

  void _scheduleScrollToActiveSlide() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToActiveSlide();
    });
  }

  Future<void> _scrollToActiveSlide() async {
    if (!widget.isVisible) return;
    final currentSlideUuid = ref.read(currentSlideUuidProvider);
    if (currentSlideUuid == null || !_scrollController.hasClients) return;

    final slideUuids = ref.read(slideDeckProvider).slideUuids;
    final activeIndex = slideUuids.indexOf(currentSlideUuid);
    if (activeIndex < 0) return;

    final targetContext = _tileKeys[currentSlideUuid]?.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        duration: _scrollDuration,
        curve: Curves.easeInOutCubicEmphasized,
      );
      return;
    }

    final viewport = _scrollController.position.viewportDimension;
    final targetOffset =
        activeIndex * _estimatedTileExtent -
        (viewport / 2) +
        (_estimatedTileExtent / 2);
    final clampedOffset = math.max(
      0.0,
      math.min(targetOffset, _scrollController.position.maxScrollExtent),
    );

    if ((_scrollController.offset - clampedOffset).abs() > 1) {
      await _scrollController.animateTo(
        clampedOffset,
        duration: _scrollDuration,
        curve: Curves.easeInOutCubicEmphasized,
      );
    }

    if (!mounted) return;

    final visibleTargetContext = _tileKeys[currentSlideUuid]?.currentContext;
    if (visibleTargetContext != null && visibleTargetContext.mounted) {
      await Scrollable.ensureVisible(
        visibleTargetContext,
        alignment: 0.5,
        duration: _scrollDuration,
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
  }
}
