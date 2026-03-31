import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/cue/slide.dart';
import '../../../data/log/logger.dart';
import '../../../services/cue/source/cue_source.dart';
import '../../../services/cue/source/local_source.dart';
import 'cue_session.dart';

/// The single source of truth for the currently active cue session.
///
/// All slide mutations go through this provider, which handles:
/// - Immutable state updates for immediate UI reactivity
/// - Debounced writes to the underlying source (DB/remote)
/// - External change integration (for future remote collaboration)
class ActiveCueSession extends AsyncNotifier<CueSession?> {
  CueSource? _source;
  Timer? _writeDebounce;
  StreamSubscription<CueSourceEvent>? _externalChangesSubscription;

  static const _writeDebounceDuration = Duration(milliseconds: 300);

  @override
  Future<CueSession?> build() async {
    // Cleanup on provider disposal
    ref.onDispose(_cleanup);

    // No cue loaded initially
    return null;
  }

  void _cleanup() {
    _writeDebounce?.cancel();
    _externalChangesSubscription?.cancel();
    _source?.dispose();
  }

  Future<void> _teardownCurrentSession({
    bool persistPendingWrites = true,
  }) async {
    if (persistPendingWrites) {
      await flushWrites();
    } else {
      _writeDebounce?.cancel();
    }

    _externalChangesSubscription?.cancel();
    _externalChangesSubscription = null;
    _source?.dispose();
    _source = null;
  }

  /// Load a cue by UUID, optionally jumping to a specific slide.
  /// This is idempotent - calling with the same UUID returns early if already loaded.
  Future<void> load(
    String uuid, {
    String? initialSlideUuid,
    bool forceReload = false,
  }) async {
    // Check if already loaded (avoid unnecessary reload)
    final current = state.value;
    if (!forceReload && current != null && current.cue.uuid == uuid) {
      // Already loaded - just update current slide if requested
      if (initialSlideUuid != null &&
          initialSlideUuid != current.currentSlideUuid) {
        state = AsyncValue.data(current.withCurrentSlide(initialSlideUuid));
      }
      return;
    }

    // Cancel any pending operations from previous session
    await _teardownCurrentSession(persistPendingWrites: !forceReload);

    // Set loading state
    state = const AsyncValue.loading();

    // Create source (for now always local, future: check cue metadata for remote)
    _source = LocalCueSource(uuid);

    try {
      // Fetch cue metadata
      final cue = await _source!.fetchCue();

      // Revival happens once here, then the same Cue object remains authoritative.
      final slides = await cue.getRevivedSlides();

      // Determine initial slide
      final initialUuid =
          initialSlideUuid != null &&
              slides.any((slide) => slide.uuid == initialSlideUuid)
          ? initialSlideUuid
          : slides.firstOrNull?.uuid;

      state = AsyncValue.data(
        CueSession(cue: cue, currentSlideUuid: initialUuid),
      );

      // Listen for external changes (relevant for future remote sources)
      _externalChangesSubscription = _source!.externalChanges.listen(
        _handleExternalChange,
      );

      log.info('Lista betöltve: ${cue.title} (${slides.length} dia)');
    } catch (e, s) {
      log.severe('Hiba lista betöltése közben:', e, s);
      state = AsyncValue.error(e, s);
    }
  }

  /// Unload the current cue (e.g., when closing the cue view)
  Future<void> unload() async {
    await _teardownCurrentSession();
    state = const AsyncValue.data(null);
  }

  /// Handle external changes from the source (for remote collaboration)
  void _handleExternalChange(CueSourceEvent event) {
    final session = state.value;
    if (session == null) return;

    switch (event) {
      case SlidesChangedEvent(:final slides):
        session.cue.replaceSlides(slides);
        final currentSlideUuid =
            slides.any((slide) => slide.uuid == session.currentSlideUuid)
            ? session.currentSlideUuid
            : slides.firstOrNull?.uuid;
        state = AsyncValue.data(session.withCurrentSlide(currentSlideUuid));
      case CurrentSlideChangedEvent(:final slideUuid):
        state = AsyncValue.data(session.withCurrentSlide(slideUuid));
      case CueMetadataChangedEvent(:final cue):
        session.cue.replaceMetadata(cue);
        state = AsyncValue.data(session.refreshed());
    }
  }

  // ============================================================
  // Navigation
  // ============================================================

  /// Navigate to next/previous slide by offset (1 = next, -1 = previous)
  /// Returns true if navigation succeeded
  bool navigate(int offset) {
    final session = state.value;
    if (session == null || session.currentIndex == null) return false;

    final newIndex = session.currentIndex! + offset;
    if (newIndex < 0 || newIndex >= session.slides.length) return false;

    state = AsyncValue.data(
      session.withCurrentSlide(session.slides[newIndex].uuid),
    );
    // Navigation doesn't trigger DB write
    return true;
  }

  /// Jump to a specific slide by UUID
  void goToSlide(String slideUuid) {
    final session = state.value;
    if (session == null) return;
    if (session.currentSlideUuid == slideUuid) return;

    // Verify slide exists
    if (!session.slides.any((s) => s.uuid == slideUuid)) return;

    state = AsyncValue.data(session.withCurrentSlide(slideUuid));
  }

  /// Go to first slide
  void goToFirst() {
    final session = state.value;
    if (session == null || session.slides.isEmpty) return;

    state = AsyncValue.data(
      session.withCurrentSlide(session.slides.first.uuid),
    );
  }

  // ============================================================
  // Slide Mutations - THE single path for all slide changes
  // ============================================================

  /// Update a slide's properties (viewType, transpose, comment, etc.)
  /// This is the main mutation method - creates immutable copy and schedules write
  void updateSlide(Slide updated) {
    final session = state.value;
    if (session == null) return;

    // Verify slide exists
    if (!session.cue.hasSlide(updated.uuid)) {
      log.warning('Tried to update non-existent slide: ${updated.uuid}');
      return;
    }

    session.cue.updateSlide(updated);
    state = AsyncValue.data(session.refreshed());

    // Debounced persistence
    _scheduleWrite();
  }

  /// Add a new slide to the cue
  void addSlide(Slide slide, {int? atIndex}) {
    final session = state.value;
    if (session == null) return;

    session.cue.addSlide(slide, atIndex: atIndex);

    // If no slide was selected, select the new one
    final finalSession = session.currentSlideUuid == null
        ? session.withCurrentSlide(slide.uuid)
        : session.refreshed();

    state = AsyncValue.data(finalSession);
    _scheduleWrite();
  }

  /// Remove a slide from the cue
  void removeSlide(String slideUuid) {
    final session = state.value;
    if (session == null) return;

    // If removing current slide, navigate to adjacent one first
    if (session.currentSlideUuid == slideUuid) {
      final currentIndex = session.currentIndex ?? 0;
      String? newCurrentUuid;

      if (session.slides.length > 1) {
        // Prefer next slide, fall back to previous
        if (currentIndex < session.slides.length - 1) {
          newCurrentUuid = session.slides[currentIndex + 1].uuid;
        } else if (currentIndex > 0) {
          newCurrentUuid = session.slides[currentIndex - 1].uuid;
        }
      }

      session.cue.removeSlide(slideUuid);
      state = AsyncValue.data(session.withCurrentSlide(newCurrentUuid));
    } else {
      session.cue.removeSlide(slideUuid);
      state = AsyncValue.data(session.refreshed());
    }

    _scheduleWrite();
  }

  /// Reorder slides (for drag-and-drop)
  void reorderSlides(int oldIndex, int newIndex) {
    final session = state.value;
    if (session == null) return;

    session.cue.reorderSlides(oldIndex, newIndex);
    state = AsyncValue.data(session.refreshed());
    _scheduleWrite();
  }

  /// Update cue metadata through the same path as slide edits.
  void updateMetadata({String? title, String? description}) {
    final session = state.value;
    if (session == null) return;
    if (title == null && description == null) return;

    session.cue.updateMetadata(title: title, description: description);
    state = AsyncValue.data(session.refreshed());
    _scheduleWrite();
  }

  // ============================================================
  // Write Scheduling
  // ============================================================

  void _scheduleWrite() {
    _writeDebounce?.cancel();
    _writeDebounce = Timer(_writeDebounceDuration, _executeWrite);
  }

  Future<void> _executeWrite() async {
    final session = state.value;
    if (session == null || _source == null) return;

    try {
      await _source!.persistCue(session.cue);
      log.fine('Lista mentve: ${session.cue.title}');
    } catch (e, s) {
      log.severe('Hiba lista mentése közben:', e, s);
      // TODO: Show user-facing error with retry option
      // For now, state remains optimistic - user can retry by making another change
    }
  }

  /// Force immediate write (e.g., before navigation away)
  Future<void> flushWrites() async {
    _writeDebounce?.cancel();
    await _executeWrite();
  }
}

final activeCueSessionProvider =
    AsyncNotifierProvider<ActiveCueSession, CueSession?>(ActiveCueSession.new);

// ============================================================
// Helper Providers for UI Convenience
// ============================================================

@immutable
class CueSlideDeckState {
  const CueSlideDeckState({required this.cueUuid, required this.slideUuids});

  const CueSlideDeckState.empty() : this(cueUuid: '', slideUuids: const []);

  factory CueSlideDeckState.fromSession(CueSession? session) {
    if (session == null) return const CueSlideDeckState.empty();

    return CueSlideDeckState(
      cueUuid: session.cue.uuid,
      slideUuids: session.slides.map((slide) => slide.uuid).toList(),
    );
  }

  final String cueUuid;
  final List<String> slideUuids;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CueSlideDeckState &&
        other.cueUuid == cueUuid &&
        listEquals(other.slideUuids, slideUuids);
  }

  @override
  int get hashCode => Object.hash(cueUuid, Object.hashAll(slideUuids));
}

@immutable
class CueSlideSnapshot {
  const CueSlideSnapshot(this.slide, this.revisionKey);

  const CueSlideSnapshot.empty() : this(null, null);

  factory CueSlideSnapshot.fromSlide(Slide? slide) {
    return CueSlideSnapshot(
      slide,
      slide == null ? null : jsonEncode(slide.toJson()),
    );
  }

  final Slide? slide;
  final String? revisionKey;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CueSlideSnapshot && other.revisionKey == revisionKey;
  }

  @override
  int get hashCode => Object.hash(slide?.uuid, revisionKey);
}

final slideDeckProvider = Provider<CueSlideDeckState>((ref) {
  return ref.watch(
    activeCueSessionProvider.select(
      (sessionAsync) => CueSlideDeckState.fromSession(sessionAsync.value),
    ),
  );
});

final currentSlideUuidProvider = Provider<String?>((ref) {
  return ref.watch(
    activeCueSessionProvider.select(
      (sessionAsync) => sessionAsync.value?.currentSlideUuid,
    ),
  );
});

final slideSnapshotProvider = Provider.family<CueSlideSnapshot, String>((
  ref,
  slideUuid,
) {
  return ref.watch(
    activeCueSessionProvider.select(
      (sessionAsync) => CueSlideSnapshot.fromSlide(
        sessionAsync.value?.cue.slideByUuid(slideUuid),
      ),
    ),
  );
});

final currentSlideSnapshotProvider = Provider<CueSlideSnapshot>((ref) {
  final slideUuid = ref.watch(currentSlideUuidProvider);
  if (slideUuid == null) return const CueSlideSnapshot.empty();
  return ref.watch(slideSnapshotProvider(slideUuid));
});

/// Watch just the current slide (convenience for widgets that only need this)
final currentSlideProvider = Provider<Slide?>((ref) {
  return ref.watch(currentSlideSnapshotProvider).slide;
});

/// Watch slide index info (for navigation UI)
final slideIndexProvider = Provider<({int index, int total})?>((ref) {
  final session = ref.watch(activeCueSessionProvider).value;
  if (session == null || session.currentIndex == null) return null;
  return (index: session.currentIndex!, total: session.slideCount);
});

/// Check if navigation is possible
final canNavigatePreviousProvider = Provider<bool>((ref) {
  return ref.watch(activeCueSessionProvider).value?.hasPrevious ?? false;
});

final canNavigateNextProvider = Provider<bool>((ref) {
  return ref.watch(activeCueSessionProvider).value?.hasNext ?? false;
});
