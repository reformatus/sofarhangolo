import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cue/slide.dart';
import '../../data/song/extensions.dart';
import '../../data/song/song.dart';
import '../cue/session/session_provider.dart';
import 'state.dart';

class ViewChooser extends ConsumerWidget {
  const ViewChooser({
    super.key,
    required this.song,
    this.songSlide,
    required this.useDropdown,
  });

  final Song song;
  final bool useDropdown;
  final SongSlide? songSlide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<SongViewType, ({IconData icon, String label, bool enabled})>
    viewTypeEntries = {
      SongViewType.svg: (
        icon: Icons.music_note_outlined,
        label: 'Kotta',
        enabled: song.hasSvg,
      ),
      SongViewType.pdf: (
        icon: Icons.audio_file_outlined,
        label: 'PDF',
        enabled: song.hasPdf,
      ),
      if (song.hasChords)
        SongViewType.chords: (
          icon: Icons.tag_outlined,
          label: 'Akkordok',
          enabled: true,
        )
      else
        SongViewType.lyrics: (
          icon: Icons.text_snippet_outlined,
          label: 'Dalszöveg',
          enabled: song.hasLyrics,
        ),
    };

    if (songSlide != null) {
      final currentSongSlide = switch (ref
          .watch(slideSnapshotProvider(songSlide!.uuid))
          .slide) {
        SongSlide currentSlide => currentSlide,
        _ => songSlide!,
      };
      final viewType = currentSongSlide.viewType;

      return LayoutBuilder(
        builder: (context, constraints) {
          if (!useDropdown) {
            return SegmentedButton<SongViewType>(
              selected: {viewType},
              onSelectionChanged: (viewTypeSet) {
                final newViewType = viewTypeSet.first;
                ref
                    .read(activeCueSessionProvider.notifier)
                    .updateSlide(
                      currentSongSlide.copyWith(viewType: newViewType),
                    );
              },
              showSelectedIcon: false,
              multiSelectionEnabled: false,
              style: ButtonStyle(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(9)),
                  ),
                ),
              ),
              segments: viewTypeEntries.entries
                  .map(
                    (entry) => ButtonSegment(
                      value: entry.key,
                      label: Text(entry.value.label),
                      icon: Icon(entry.value.icon),
                      enabled: entry.value.enabled,
                      tooltip: !entry.value.enabled ? 'Nem elérhető' : null,
                    ),
                  )
                  .toList(),
            );
          }

          return FilledButton(
            style: ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
              enableFeedback: false,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStatePropertyAll(Colors.transparent),
            ),
            focusNode: FocusNode(skipTraversal: true),
            onPressed: () {},
            child: DropdownButton<SongViewType>(
              borderRadius: BorderRadius.circular(15),
              isDense: true,
              padding: EdgeInsets.only(top: 5, bottom: 5, left: 15, right: 5),
              underline: SizedBox.shrink(),
              focusColor: Colors.transparent,
              icon: Icon(
                Icons.arrow_drop_down_rounded,
                color: Theme.of(context).colorScheme.inverseSurface,
              ),
              autofocus: false,
              value: viewType,
              onChanged: (newViewType) {
                if (newViewType == null) return;
                ref
                    .read(activeCueSessionProvider.notifier)
                    .updateSlide(
                      currentSongSlide.copyWith(viewType: newViewType),
                    );
              },
              items: viewTypeEntries.entries
                  .where((entry) => entry.value.enabled)
                  .map(
                    (entry) => DropdownMenuItem(
                      enabled: entry.value.enabled,
                      value: entry.key,
                      child: Row(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Icon(
                              entry.value.icon,
                              color: Theme.of(
                                context,
                              ).colorScheme.inverseSurface,
                            ),
                          ),
                          Text(
                            entry.value.label,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.inverseSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
        },
      );
    }

    final viewTypeAsync = ref.watch(viewTypeForProvider(song, songSlide));

    if (!viewTypeAsync.hasValue) return const SizedBox.shrink();
    final viewType = viewTypeAsync.requireValue;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!useDropdown) {
          return SegmentedButton<SongViewType>(
            selected: {viewType},
            onSelectionChanged: (viewTypeSet) {
              final newViewType = viewTypeSet.first;
              ref
                  .read(viewTypeForProvider(song, songSlide).notifier)
                  .setTo(newViewType);
            },
            showSelectedIcon: false,
            multiSelectionEnabled: false,
            style: ButtonStyle(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(9)),
                ),
              ),
            ),
            segments: viewTypeEntries.entries
                .map(
                  (entry) => ButtonSegment(
                    value: entry.key,
                    label: Text(entry.value.label),
                    icon: Icon(entry.value.icon),
                    enabled: entry.value.enabled,
                    tooltip: !entry.value.enabled ? 'Nem elérhető' : null,
                  ),
                )
                .toList(),
          );
        } else {
          return FilledButton(
            style: ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
              enableFeedback: false,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStatePropertyAll(Colors.transparent),
            ),
            focusNode: FocusNode(skipTraversal: true),
            onPressed: () {},
            child: DropdownButton<SongViewType>(
              borderRadius: BorderRadius.circular(15),
              isDense: true,
              padding: EdgeInsets.only(top: 5, bottom: 5, left: 15, right: 5),
              underline: SizedBox.shrink(),
              focusColor: Colors.transparent,
              icon: Icon(
                Icons.arrow_drop_down_rounded,
                color: Theme.of(context).colorScheme.inverseSurface,
              ),
              autofocus: false,
              value: viewType,
              onChanged: (newViewType) {
                if (newViewType == null) return;
                ref
                    .read(viewTypeForProvider(song, songSlide).notifier)
                    .setTo(newViewType);
              },
              items: viewTypeEntries.entries
                  .where((entry) => entry.value.enabled)
                  .map(
                    (entry) => DropdownMenuItem(
                      enabled: entry.value.enabled,
                      value: entry.key,
                      child: Row(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Icon(
                              entry.value.icon,
                              color: Theme.of(
                                context,
                              ).colorScheme.inverseSurface,
                            ),
                          ),
                          Text(
                            entry.value.label,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.inverseSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
        }
      },
    );
  }
}
