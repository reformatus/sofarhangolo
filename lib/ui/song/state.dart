import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/cue/slide.dart';
import '../../data/song/extensions.dart';
import '../../data/song/song.dart';
import '../../services/assets/downloaded.dart';
import '../../services/connectivity/provider.dart';
import '../../services/preferences/providers/song_view_order.dart';
import '../cue/session/session_provider.dart';

part 'state.g.dart';

enum SongViewType {
  svg('svg', requiresAsset: true),
  pdf('pdf', requiresAsset: true),
  lyrics('lyrics'),
  chords('chords');

  final String type;
  final bool requiresAsset;

  const SongViewType(this.type, {this.requiresAsset = false});
  factory SongViewType.fromString(String type) {
    return SongViewType.values.firstWhere((e) => e.type == type);
  }
}

/// Provider for view type of a song.
///
/// Behavior depends on context:
/// - **In cue context** (`songSlide != null`): Derives state from ActiveCueSession.
///   Changes route through session for persistence.
/// - **Standalone** (`songSlide == null`): Holds independent local state.
///   Computes initial value based on preferences and connectivity.
@Riverpod(keepAlive: true)
class ViewTypeFor extends _$ViewTypeFor {
  @override
  Future<SongViewType> build(Song song, SongSlide? songSlide) async {
    // CASE 1: In cue context - derive from session
    if (songSlide != null) {
      final session = ref.watch(activeCueSessionProvider).value;
      if (session != null) {
        // Find the current version of this slide in the session
        final currentSlide = session.slides
            .whereType<SongSlide>()
            .where((s) => s.uuid == songSlide.uuid)
            .firstOrNull;

        if (currentSlide != null) {
          return currentSlide.viewType;
        }
      }
      // Fallback to slide's stored value if session not ready
      return songSlide.viewType;
    }

    // CASE 2: Standalone song view - compute default based on preferences
    final songViewOrder = ref
        .watch(songViewOrderPreferencesProvider)
        .songViewOrder;

    SongViewType result;
    if (ref.read(connectionProvider) == ConnectionType.offline) {
      List<String> downloadedAssets = await downloadedAssetsForSong(song);

      result = songViewOrder.firstWhere(
        (v) =>
            (song.availableViews.contains(v.name)) &&
            (!v.requiresAsset ||
                (v.requiresAsset && downloadedAssets.contains(v.name))),
      );
    } else {
      result = songViewOrder.firstWhere(
        (v) => song.availableViews.contains(v.name),
      );
    }

    if (result == SongViewType.lyrics && song.hasChords) {
      return SongViewType.chords;
    } else {
      return result;
    }
  }

  /// Set view type - routes through session if in cue context
  void setTo(SongViewType newValue) {
    if (songSlide != null) {
      // Route through session for cue context
      final notifier = ref.read(activeCueSessionProvider.notifier);
      final session = ref.read(activeCueSessionProvider).value;

      if (session != null) {
        // Find current slide state and create updated copy
        final currentSlide = session.slides
            .whereType<SongSlide>()
            .where((s) => s.uuid == songSlide!.uuid)
            .firstOrNull;

        if (currentSlide != null) {
          notifier.updateSlide(currentSlide.copyWith(viewType: newValue));
          return; // Session update will trigger rebuild via ref.watch
        }
      }
    }
    // Standalone: direct state update
    if (newValue == SongViewType.lyrics && song.hasChords) {
      state = AsyncValue.data(SongViewType.chords);
    } else {
      state = AsyncValue.data(newValue);
    }
  }
}
