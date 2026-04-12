import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/cue/slide.dart';
import '../../common/centered_hint.dart';
import '../session/session_provider.dart';
import '../slide_views/song.dart';
import '../slide_views/unknown.dart';
import 'gesture_adapter.dart';

typedef SlideViewBuildLogger = void Function(String slideUuid);
typedef SlideViewTransitionLogger =
    void Function({
      required String? settledSlideUuid,
      required String? targetSlideUuid,
      required double transitionProgress,
      required int transitionDirection,
    });

@visibleForTesting
SlideViewBuildLogger? debugSlideViewBuildLogger;

@visibleForTesting
SlideViewTransitionLogger? debugSlideViewTransitionLogger;

class SlideView extends ConsumerStatefulWidget {
  const SlideView({super.key});

  @override
  ConsumerState<SlideView> createState() => _SlideViewState();
}

class _SlideViewState extends ConsumerState<SlideView>
    with SingleTickerProviderStateMixin {
  static const double _releaseCommitProgress = 0.5;
  static const double _dragCommitProgress = 1.0;
  static const double _velocityThreshold = 700;

  late final AnimationController _settleController;
  int _settleGeneration = 0;
  final Map<String, Widget> _retainedSlideWidgets = <String, Widget>{};

  List<String> slideUuids = const [];
  String cueUuid = '';
  String? settledSlideUuid;
  String? transitionTargetSlideUuid;
  int transitionDirection = 1;
  double transitionProgress = 0;
  double dragViewportWidth = 1;
  bool isDragging = false;
  bool gestureLocked = false;
  bool transitionShouldNotifySession = false;

  @override
  void initState() {
    super.initState();
    _settleController =
        AnimationController(
          vsync: this,
          lowerBound: -1,
          upperBound: 1,
          duration: Durations.medium2,
        )..addListener(() {
          if (!_settleController.isAnimating || !mounted) return;
          setState(() {
            transitionProgress = _settleController.value;
          });
        });

    replaceSlideDeck(ref.read(slideDeckProvider));

    ref.listenManual(slideDeckProvider, (_, nextDeck) {
      if (!mounted) return;
      replaceSlideDeck(nextDeck, notify: true);
    });

    ref.listenManual(currentSlideUuidProvider, (_, nextSlideUuid) {
      syncRequestedSlide(nextSlideUuid);
    });
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  void replaceSlideDeck(CueSlideDeckState deck, {bool notify = false}) {
    final previousCueUuid = cueUuid;
    final nextSettledSlideUuid = resolvedSlideUuidFor(
      ref.read(currentSlideUuidProvider),
      inSlideUuids: deck.slideUuids,
    );

    void updateState() {
      stopSettleAnimation();
      if (previousCueUuid != deck.cueUuid) {
        _retainedSlideWidgets.clear();
      } else {
        _retainedSlideWidgets.removeWhere(
          (slideUuid, _) => !deck.slideUuids.contains(slideUuid),
        );
      }
      slideUuids = deck.slideUuids;
      cueUuid = deck.cueUuid;
      settledSlideUuid = nextSettledSlideUuid;
      clearTransitionState();
      if (nextSettledSlideUuid != null) {
        warmSlide(nextSettledSlideUuid);
      }
    }

    if (notify) {
      setState(updateState);
    } else {
      updateState();
    }
  }

  String? resolvedSlideUuidFor(
    String? currentSlideUuid, {
    required List<String> inSlideUuids,
  }) {
    if (inSlideUuids.isEmpty) return null;

    if (currentSlideUuid != null && inSlideUuids.contains(currentSlideUuid)) {
      return currentSlideUuid;
    }

    return inSlideUuids.first;
  }

  String? neighborSlideUuidForDirection(
    int direction, {
    String? fromSlideUuid,
  }) {
    final anchorSlideUuid = fromSlideUuid ?? settledSlideUuid;
    if (anchorSlideUuid == null) return null;

    final currentIndex = slideUuids.indexOf(anchorSlideUuid);
    if (currentIndex == -1) return null;

    final targetIndex = currentIndex + direction;
    if (targetIndex < 0 || targetIndex >= slideUuids.length) return null;

    return slideUuids[targetIndex];
  }

  int directionFor({
    required String? fromSlideUuid,
    required String toSlideUuid,
    required List<String> inSlideUuids,
  }) {
    if (fromSlideUuid == null) return 1;

    final fromIndex = inSlideUuids.indexOf(fromSlideUuid);
    final toIndex = inSlideUuids.indexOf(toSlideUuid);
    if (fromIndex == -1 || toIndex == -1 || toIndex == fromIndex) {
      return 1;
    }

    return toIndex > fromIndex ? 1 : -1;
  }

  void warmSlide(String slideUuid) {
    _retainedSlideWidgets.putIfAbsent(
      slideUuid,
      () => _RetainedSlidePage(
        key: ValueKey('retained-slide/$cueUuid/$slideUuid'),
        slideUuid: slideUuid,
        cueUuid: cueUuid,
      ),
    );
  }

  void syncRequestedSlide(String? currentSlideUuid) {
    final nextRequestedSlideUuid = resolvedSlideUuidFor(
      currentSlideUuid,
      inSlideUuids: slideUuids,
    );
    if (nextRequestedSlideUuid == null) {
      return;
    }

    if (nextRequestedSlideUuid == settledSlideUuid &&
        transitionTargetSlideUuid == null) {
      return;
    }

    if (isDragging || gestureLocked) {
      return;
    }

    if (transitionTargetSlideUuid == nextRequestedSlideUuid &&
        _settleController.isAnimating) {
      return;
    }

    if (_settleController.isAnimating && !transitionShouldNotifySession) {
      stopSettleAnimation();
      setState(() {
        warmSlide(nextRequestedSlideUuid);
        settledSlideUuid = nextRequestedSlideUuid;
        clearTransitionState();
      });
      return;
    }

    if (_settleController.isAnimating && transitionShouldNotifySession) {
      stopSettleAnimation();
    }

    if (settledSlideUuid == null ||
        nextRequestedSlideUuid == settledSlideUuid) {
      setState(() {
        settledSlideUuid = nextRequestedSlideUuid;
        clearTransitionState();
        warmSlide(nextRequestedSlideUuid);
      });
      return;
    }

    warmSlide(nextRequestedSlideUuid);

    setState(() {
      transitionTargetSlideUuid = nextRequestedSlideUuid;
      transitionDirection = directionFor(
        fromSlideUuid: settledSlideUuid,
        toSlideUuid: nextRequestedSlideUuid,
        inSlideUuids: slideUuids,
      );
      transitionProgress = 0;
      transitionShouldNotifySession = false;
    });

    animateTransitionTo(
      fullProgressForDirection(transitionDirection),
      commitToTarget: true,
      notifySession: false,
    );
  }

  void handleHorizontalDragStart() {
    if (_settleController.isAnimating && !transitionShouldNotifySession) {
      return;
    }

    stopSettleAnimation();
    isDragging = true;
    gestureLocked = false;
  }

  void handleHorizontalDragUpdate(double deltaDx) {
    if (!isDragging ||
        gestureLocked ||
        deltaDx == 0 ||
        dragViewportWidth <= 0) {
      return;
    }

    final nextProgress = clampTransitionProgress(
      transitionProgress + (deltaDx / dragViewportWidth),
    );

    if (nextProgress == 0) {
      if (transitionTargetSlideUuid == null && transitionProgress == 0) {
        return;
      }
      setState(clearTransitionState);
      return;
    }

    final nextDirection = directionForProgress(nextProgress);
    final targetSlideUuid = neighborSlideUuidForDirection(nextDirection);
    if (targetSlideUuid == null) {
      setState(clearTransitionState);
      return;
    }

    warmSlide(targetSlideUuid);

    setState(() {
      transitionDirection = nextDirection;
      transitionTargetSlideUuid = targetSlideUuid;
      transitionProgress = nextProgress;
      transitionShouldNotifySession = true;
    });

    if (nextProgress.abs() >= _dragCommitProgress) {
      commitTransitionImmediately(notifySession: true);
    }
  }

  void handleHorizontalDragEnd(double velocityDx) {
    if (gestureLocked) {
      isDragging = false;
      gestureLocked = false;
      return;
    }

    isDragging = false;

    if (transitionTargetSlideUuid == null || transitionProgress == 0) {
      clearTransitionState();
      return;
    }

    final activeDirection = directionForProgress(transitionProgress);
    final flingCommits =
        (activeDirection == 1 && velocityDx <= -_velocityThreshold) ||
        (activeDirection == -1 && velocityDx >= _velocityThreshold);
    final shouldCommit =
        transitionProgress.abs() >= _releaseCommitProgress || flingCommits;

    animateTransitionTo(
      shouldCommit ? fullProgressForDirection(activeDirection) : 0,
      commitToTarget: shouldCommit,
      notifySession: shouldCommit && transitionShouldNotifySession,
    );
  }

  void handleHorizontalDragCancel() {
    if (gestureLocked) {
      isDragging = false;
      gestureLocked = false;
      return;
    }

    isDragging = false;

    if (transitionTargetSlideUuid == null || transitionProgress == 0) {
      clearTransitionState();
      return;
    }

    animateTransitionTo(0, commitToTarget: false, notifySession: false);
  }

  void stopSettleAnimation() {
    _settleGeneration += 1;
    _settleController.stop();
  }

  void clearTransitionState() {
    transitionTargetSlideUuid = null;
    transitionProgress = 0;
    transitionShouldNotifySession = false;
  }

  Duration settleDurationFor(double delta) {
    final milliseconds = (Durations.medium2.inMilliseconds * delta)
        .round()
        .clamp(80, Durations.medium2.inMilliseconds);
    return Duration(milliseconds: milliseconds);
  }

  int directionForProgress(double progress) {
    return progress < 0 ? 1 : -1;
  }

  double fullProgressForDirection(int direction) {
    return direction == 1 ? -_dragCommitProgress : _dragCommitProgress;
  }

  double clampTransitionProgress(double proposedProgress) {
    final canGoNext = neighborSlideUuidForDirection(1) != null;
    final canGoPrevious = neighborSlideUuidForDirection(-1) != null;

    return proposedProgress
        .clamp(
          canGoNext ? -_dragCommitProgress : 0.0,
          canGoPrevious ? _dragCommitProgress : 0.0,
        )
        .toDouble();
  }

  Future<void> animateTransitionTo(
    double targetProgress, {
    required bool commitToTarget,
    required bool notifySession,
  }) async {
    final targetSlideUuid = transitionTargetSlideUuid;
    if (targetSlideUuid == null) {
      clearTransitionState();
      return;
    }

    if (transitionProgress == targetProgress) {
      if (commitToTarget) {
        finishCommittedTransition(
          targetSlideUuid,
          notifySession: notifySession,
        );
      } else {
        setState(clearTransitionState);
      }
      return;
    }

    stopSettleAnimation();
    final settleGeneration = _settleGeneration;
    _settleController.value = transitionProgress;

    await _settleController.animateTo(
      targetProgress,
      duration: settleDurationFor((targetProgress - transitionProgress).abs()),
      curve: Curves.easeOutCubic,
    );

    if (!mounted || settleGeneration != _settleGeneration) {
      return;
    }

    if (commitToTarget) {
      finishCommittedTransition(targetSlideUuid, notifySession: notifySession);
    } else {
      setState(clearTransitionState);
    }
  }

  void commitTransitionImmediately({required bool notifySession}) {
    final targetSlideUuid = transitionTargetSlideUuid;
    if (targetSlideUuid == null) return;

    stopSettleAnimation();
    setState(() {
      settledSlideUuid = targetSlideUuid;
      clearTransitionState();
      gestureLocked = true;
    });

    if (notifySession) {
      ref.read(activeCueSessionProvider.notifier).goToSlide(targetSlideUuid);
    }
  }

  void finishCommittedTransition(
    String targetSlideUuid, {
    required bool notifySession,
  }) {
    setState(() {
      settledSlideUuid = targetSlideUuid;
      clearTransitionState();
    });

    if (notifySession) {
      ref.read(activeCueSessionProvider.notifier).goToSlide(targetSlideUuid);
    }
  }

  double slideOffsetFor(int slideRoleDirection) {
    if (slideRoleDirection == 0) {
      return transitionProgress * dragViewportWidth;
    }

    final effectiveDirection = transitionProgress == 0
        ? transitionDirection
        : directionForProgress(transitionProgress);

    if (effectiveDirection == 1) {
      return (1 + transitionProgress) * dragViewportWidth;
    }

    return -(1 - transitionProgress) * dragViewportWidth;
  }

  Widget buildSlideSlot({
    required String slideUuid,
    required bool visible,
    required double dx,
  }) {
    return _RetainedSlideSlot(
      key: ValueKey('slide-slot/$cueUuid/$slideUuid'),
      visible: visible,
      dx: dx,
      child: _retainedSlideWidgets[slideUuid]!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSlideUuid = settledSlideUuid;

    debugSlideViewTransitionLogger?.call(
      settledSlideUuid: settledSlideUuid,
      targetSlideUuid: transitionTargetSlideUuid,
      transitionProgress: transitionProgress,
      transitionDirection: transitionDirection,
    );

    return Theme(
      data: Theme.of(context),
      child: Hero(
        tag: 'SlideView',
        child: slideUuids.isEmpty
            ? CenteredHint(
                'Keress és adj hozzá dalokat a listához a Daltár oldalon',
                iconData: Icons.library_music,
              )
            : currentSlideUuid == null
            ? const SizedBox.shrink()
            : LayoutBuilder(
                builder: (context, constraints) {
                  dragViewportWidth = constraints.maxWidth;
                  final targetSlideUuid = transitionTargetSlideUuid;
                  final showTransition = targetSlideUuid != null;
                  final hiddenSlideUuids = _retainedSlideWidgets.keys.where(
                    (slideUuid) =>
                        slideUuid != currentSlideUuid &&
                        slideUuid != targetSlideUuid,
                  );

                  return CueSlideGestureAdapter(
                    enabled: slideUuids.length > 1,
                    onHorizontalDragStart: handleHorizontalDragStart,
                    onHorizontalDragUpdate: handleHorizontalDragUpdate,
                    onHorizontalDragEnd: handleHorizontalDragEnd,
                    onHorizontalDragCancel: handleHorizontalDragCancel,
                    child: ClipRect(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          for (final slideUuid in hiddenSlideUuids)
                            buildSlideSlot(
                              slideUuid: slideUuid,
                              visible: false,
                              dx: 0,
                            ),
                          if (showTransition)
                            buildSlideSlot(
                              slideUuid: targetSlideUuid,
                              visible: true,
                              dx: slideOffsetFor(transitionDirection),
                            ),
                          buildSlideSlot(
                            slideUuid: currentSlideUuid,
                            visible: true,
                            dx: showTransition ? slideOffsetFor(0) : 0,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _RetainedSlideSlot extends StatelessWidget {
  const _RetainedSlideSlot({
    required this.visible,
    required this.dx,
    required this.child,
    super.key,
  });

  final bool visible;
  final double dx;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: TickerMode(
          enabled: visible,
          child: Offstage(
            offstage: !visible,
            child: Transform.translate(offset: Offset(dx, 0), child: child),
          ),
        ),
      ),
    );
  }
}

class _RetainedSlidePage extends ConsumerWidget {
  const _RetainedSlidePage({
    required this.slideUuid,
    required this.cueUuid,
    super.key,
  });

  final String slideUuid;
  final String cueUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugSlideViewBuildLogger?.call(slideUuid);

    final slide = ref.watch(slideSnapshotProvider(slideUuid)).slide;

    if (slide == null) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: switch (slide) {
        SongSlide songSlide => SongSlideView(songSlide, cueUuid),
        UnknownTypeSlide unknownSlide => UnknownTypeSlideView(unknownSlide),
      },
    );
  }
}
