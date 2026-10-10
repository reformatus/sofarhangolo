import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/song/song.dart';
import '../../../services/songs/original_status.dart';
import '../../common/key_text.dart';

/// Right-pane song details: the original bank song (for copies) and the
/// song's keys.
class DetailsPane extends StatelessWidget {
  const DetailsPane({super.key, required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 20,
        children: [
          _OriginalSongCard(song),
          _KeySection(song),
        ],
      ),
    );
  }
}

class _OriginalSongCard extends ConsumerWidget {
  const _OriginalSongCard(this.song);

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(originalSongStatusProvider(song)).value;
    if (status == null) return const SizedBox.shrink();

    final original = ref.watch(originalSongProvider(song)).value;
    final colors = Theme.of(context).colorScheme;
    final onContainer = colors.onTertiaryContainer;

    final (statusIcon, statusLabel) = switch (status) {
      OriginalSongStatus.unchanged => (
        Icons.check_circle_outline,
        'Megegyezik az eredetivel.',
      ),
      OriginalSongStatus.changed => (
        Icons.sync_problem_outlined,
        'Megváltozott a másolás óta.',
      ),
      OriginalSongStatus.missing => (
        Icons.link_off,
        'Az eredeti dal már nincs meg.',
      ),
    };

    return Card(
      margin: EdgeInsets.zero,
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 18, color: onContainer),
                const SizedBox(width: 8),
                Text(
                  'Eredeti dal',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: onContainer),
                ),
              ],
            ),
            Text(
              original?.title ?? 'Az eredeti dal nem elérhető',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: onContainer),
            ),
            Row(
              children: [
                Icon(statusIcon, size: 16, color: onContainer),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    statusLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: onContainer),
                  ),
                ),
              ],
            ),
            if (original != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: onContainer),
                  onPressed: () => context.push('/song/${original.uuid}'),
                  child: const Text('Eredeti megtekintése'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeySection extends StatelessWidget {
  const _KeySection(this.song);

  final Song song;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text('Hangnem', style: Theme.of(context).textTheme.titleMedium),
        if (song.keyField.isEmpty)
          Text(
            'Nincs hangnem megadva.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in song.keyField)
                Chip(label: Text(displayKeyField(key))),
            ],
          ),
        // TODO(editor): make the song's keys editable (needs a key picker).
      ],
    );
  }
}
