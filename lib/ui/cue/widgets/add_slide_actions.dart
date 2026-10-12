import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/cue/slide.dart';
import '../../../data/log/logger.dart';
import '../../../data/song/song.dart';
import '../../../services/cue/write_cue.dart';
import '../../../services/songs/write_song.dart';
import '../../../services/ui/messenger_service.dart';
import '../../song/state.dart';
import '../session/session_provider.dart';

/// The "add songs" options shown at the end of the cue editor's slide list:
/// create a new local song, or pick an existing one from the songs page.
class CueAddSlideActions extends ConsumerStatefulWidget {
  const CueAddSlideActions({super.key});

  @override
  ConsumerState<CueAddSlideActions> createState() => _CueAddSlideActionsState();
}

class _CueAddSlideActionsState extends ConsumerState<CueAddSlideActions> {
  bool _adding = false;

  /// Creates a new (empty) local song, appends it to the active cue and opens
  /// its editor so it can be filled in.
  Future<void> _addNewSong() async {
    final session = ref.read(activeCueSessionProvider).value;
    if (session == null || _adding) return;

    setState(() => _adding = true);
    try {
      final song = await writeLocalSong(Song.local(title: 'Új dal'));
      final defaultViewType = await ref.read(
        viewTypeForProvider(song, null).future,
      );
      await addSlideToCue(
        SongSlide.from(song, viewType: defaultViewType),
        session.cue,
        ref: ref,
      );

      if (!mounted) return;
      context.push('/song/local/${song.uuid}');
    } catch (error, stackTrace) {
      log.warning(
        'Nem sikerült saját dalt hozzáadni a listához.',
        error,
        stackTrace,
      );
      messengerService.showSnackBarReplacingCurrent(
        const SnackBar(
          showCloseIcon: true,
          content: Text('Nem sikerült hozzáadni dalt a listához.'),
          duration: Duration(seconds: 4),
        ),
        forceHideAfter: const Duration(seconds: 4),
      );
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  /// The cue stays open, so the songs list can add straight into it.
  void _openSongsPage() => context.push('/bank');

  @override
  Widget build(BuildContext context) {
    // [shrinkWrap] keeps a chip's box at its painted size, so the paddings below
    // are exactly the gaps that are seen (a padded tap target would add the same
    // invisible margin around every chip, swallowing the group's top gap).
    const tapTarget = MaterialTapTargetSize.shrinkWrap;

    return Padding(
      // One related group closing the list: a clearly larger gap above it than
      // between the chips, so it does not look glued to the last slide.
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            materialTapTargetSize: tapTarget,
            avatar: _adding
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.note_add_outlined, size: 18),
            label: const Text('Új dal hozzáadása'),
            onPressed: _adding ? null : _addNewSong,
          ),
          ActionChip(
            materialTapTargetSize: tapTarget,
            avatar: const Icon(Icons.playlist_add, size: 18),
            label: const Text('Meglévő dal hozzáadása'),
            onPressed: _openSongsPage,
          ),
        ],
      ),
    );
  }
}
