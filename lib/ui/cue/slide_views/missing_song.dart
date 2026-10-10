import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/cue/slide.dart';
import '../../common/error/card.dart';
import '../session/session_provider.dart';

/// Single source of the missing-song wording, shared by the slide-list tile
/// and the centered slide view so the message is only phrased once.
const String missingSongTitle = 'A dal nem található';
const String missingSongMessage =
    'Ez a dal nincs meg ezen az eszközön. Eltávolíthatod a listából.';
const String missingSongRemoveLabel = 'Eltávolítás a listából';

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
        title: const Text(missingSongTitle),
        subtitle: const Text(missingSongMessage),
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

/// Full-slide state for a song slide whose song is missing. The remove action
/// lives here, so no separate sidebar is needed.
class MissingSongView extends ConsumerWidget {
  const MissingSongView({required this.songSlide, super.key});

  final SongSlide songSlide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LErrorCard(
                type: LErrorType.warning,
                title: missingSongTitle,
                icon: Icons.music_off,
                message: missingSongMessage,
                showReportButton: false,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => ref
                    .read(activeCueSessionProvider.notifier)
                    .removeSlide(songSlide.uuid),
                icon: const Icon(Icons.delete_outline),
                label: const Text(missingSongRemoveLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
