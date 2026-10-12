import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/song/song.dart';
import '../../data/song/transpose.dart';
import '../common/sidebar/sidebar.dart';
import '../cue/session/cue_session.dart';
import '../cue/session/session_provider.dart';
import 'add_to_cue_search.dart';
import 'cue_actions.dart';
import 'state.dart';

class SongCueActions extends StatelessWidget {
  const SongCueActions({
    super.key,
    required this.song,
    required this.isDesktop,
    this.showOpenCueAction = false,
    required this.viewType,
    required this.transpose,
  });

  final Song song;
  final bool isDesktop;
  final bool showOpenCueAction;
  final SongViewType viewType;
  final SongTranspose? transpose;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      if (showOpenCueAction) {
        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(
              child: AddToCueSearch(
                song: song,
                isDesktop: false,
                viewType: viewType,
                transpose: transpose ?? SongTranspose(),
              ),
            ),
            const SizedBox(width: 8),
            OpenCueActionControl(song: song, transpose: transpose),
          ],
        );
      }

      return AddToCueSearch(
        song: song,
        isDesktop: false,
        viewType: viewType,
        transpose: transpose ?? SongTranspose(),
      );
    }

    // The search box sits first so the "already added" hint (or the
    // add-to-open-cue button) reads as its outcome, separated by the
    // sidebar's usual small gap.
    return SidebarColumn(
      gap: 10,
      children: [
        AddToCueSearch(
          song: song,
          isDesktop: true,
          viewType: viewType,
          transpose: transpose ?? SongTranspose(),
        ),
        OpenCueActionControl(song: song, transpose: transpose),
      ],
    );
  }
}

class OpenCueActionControl extends ConsumerStatefulWidget {
  const OpenCueActionControl({
    super.key,
    required this.song,
    required this.transpose,
  });

  final Song song;
  final SongTranspose? transpose;

  @override
  ConsumerState<OpenCueActionControl> createState() => _OpenCueActionState();
}

class _OpenCueActionState extends ConsumerState<OpenCueActionControl> {
  bool _isAdding = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(
      activeCueSessionProvider.select((sessionAsync) => sessionAsync.value),
    );
    final cueActionState = SongCueActionState.fromSession(session, widget.song);

    if (!cueActionState.hasActiveCue) {
      return const SizedBox.shrink();
    }

    if (cueActionState.showOpenCueAddedState) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              size: 18,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                'Megnyitott listához adva',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      );
    }

    return FilledButton.tonalIcon(
      onPressed: _isAdding || session == null
          ? null
          : () => _handleAddToOpenCue(session),
      icon: _isAdding
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.playlist_add),
      label: const Text('Hozzáadás megnyitott listához'),
    );
  }

  Future<void> _handleAddToOpenCue(CueSession session) async {
    setState(() => _isAdding = true);
    try {
      await addSongToActiveCue(
        ref: ref,
        song: widget.song,
        transpose: widget.transpose,
        session: session,
      );
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }
}
