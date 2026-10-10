import 'package:flutter/material.dart';

import '../../../data/cue/slide.dart';
import '../../common/error/card.dart';

/// Tile for a song slide whose song is missing on this device.
class MissingSongTile extends StatelessWidget {
  const MissingSongTile(
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
      child: ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(slide.title),
        subtitle: const Text('A dal nem található ezen az eszközön.'),
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
        tileColor: Theme.of(context).colorScheme.errorContainer,
        selectedTileColor: Theme.of(context).colorScheme.onPrimary,
        textColor: Theme.of(context).colorScheme.onErrorContainer,
      ),
    );
  }
}

/// Full-slide error state for a song slide whose song is missing.
class MissingSongView extends StatelessWidget {
  const MissingSongView({required this.songSlide, super.key});

  final SongSlide songSlide;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LErrorCard(
        type: LErrorType.warning,
        title: 'A dal nem található',
        icon: Icons.music_off,
        message:
            '„${songSlide.title}” jelenleg nincs meg ezen az eszközön. '
            'Lehet, hogy törölték, vagy még nem töltődött le.',
        showReportButton: false,
      ),
    );
  }
}
