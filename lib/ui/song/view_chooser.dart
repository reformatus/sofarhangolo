import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cue/slide.dart';
import '../../data/song/extensions.dart';
import '../../data/song/song.dart';
import '../cue/session/session_provider.dart';
import 'state.dart';

/// The icon used for [viewType] wherever the view is presented: the segmented
/// chooser and the editor's attachment empty state. One source keeps them in
/// sync.
IconData viewTypeIcon(SongViewType viewType) => switch (viewType) {
  SongViewType.svg => Icons.music_note_outlined,
  SongViewType.pdf => Icons.audio_file_outlined,
  SongViewType.lyrics => Icons.text_snippet_outlined,
  SongViewType.chords => Icons.tag_outlined,
};

/// One selectable view: its type, label and whether it can be picked.
typedef ViewTypeEntry = ({SongViewType type, String label, bool enabled});

class ViewChooser extends ConsumerWidget {
  const ViewChooser({
    super.key,
    required this.song,
    this.songSlide,
    required this.useDropdown,
    this.allowUnavailableViews = false,
  });

  final Song song;
  final bool useDropdown;
  final SongSlide? songSlide;

  /// Whether views without a backing asset (e.g. SVG/PDF on a local song)
  /// are selectable anyway. The editor needs this to reach the attachment
  /// views before anything is attached; the song page keeps them disabled.
  final bool allowUnavailableViews;

  List<ViewTypeEntry> get _entries => [
    (
      type: SongViewType.svg,
      label: 'Kotta',
      enabled: song.hasSvg || allowUnavailableViews,
    ),
    (
      type: SongViewType.pdf,
      label: 'PDF',
      enabled: song.hasPdf || allowUnavailableViews,
    ),
    if (song.hasChords)
      (type: SongViewType.chords, label: 'Akkordok', enabled: true)
    else
      (
        type: SongViewType.lyrics,
        label: 'Dalszöveg',
        enabled: song.hasLyrics || allowUnavailableViews,
      ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = _entries;

    if (songSlide != null) {
      final currentSongSlide = switch (ref
          .watch(slideSnapshotProvider(songSlide!.uuid))
          .slide) {
        SongSlide currentSlide => currentSlide,
        _ => songSlide!,
      };

      return _chooser(
        entries,
        selected: currentSongSlide.viewType,
        onChanged: (viewType) => ref
            .read(activeCueSessionProvider.notifier)
            .updateSlide(currentSongSlide.copyWith(viewType: viewType)),
      );
    }

    final viewTypeAsync = ref.watch(viewTypeForProvider(song, songSlide));
    if (!viewTypeAsync.hasValue) return const SizedBox.shrink();

    return _chooser(
      entries,
      selected: viewTypeAsync.requireValue,
      onChanged: (viewType) =>
          ref.read(viewTypeForProvider(song, songSlide).notifier).setTo(viewType),
    );
  }

  Widget _chooser(
    List<ViewTypeEntry> entries, {
    required SongViewType selected,
    required ValueChanged<SongViewType> onChanged,
  }) {
    if (!useDropdown) {
      return _ViewTypeSegmented(
        entries: entries,
        selected: selected,
        onChanged: onChanged,
      );
    }
    return _ViewTypeDropdown(
      entries: entries.where((entry) => entry.enabled).toList(),
      selected: selected,
      onChanged: onChanged,
    );
  }
}

class _ViewTypeSegmented extends StatelessWidget {
  const _ViewTypeSegmented({
    required this.entries,
    required this.selected,
    required this.onChanged,
  });

  final List<ViewTypeEntry> entries;
  final SongViewType selected;
  final ValueChanged<SongViewType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<SongViewType>(
      selected: {selected},
      onSelectionChanged: (viewTypes) => onChanged(viewTypes.first),
      showSelectedIcon: false,
      multiSelectionEnabled: false,
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(9)),
          ),
        ),
      ),
      segments: [
        for (final entry in entries)
          ButtonSegment(
            value: entry.type,
            label: Text(entry.label),
            icon: Icon(viewTypeIcon(entry.type)),
            enabled: entry.enabled,
            tooltip: !entry.enabled ? 'Nem elérhető' : null,
          ),
      ],
    );
  }
}

/// The compact form of the view switcher: a filled button whose label is the
/// current view and whose menu lists the available ones.
class _ViewTypeDropdown extends StatelessWidget {
  const _ViewTypeDropdown({
    required this.entries,
    required this.selected,
    required this.onChanged,
  });

  final List<ViewTypeEntry> entries;
  final SongViewType selected;
  final ValueChanged<SongViewType> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return FilledButton(
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        enableFeedback: false,
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      focusNode: FocusNode(skipTraversal: true),
      onPressed: () {},
      child: Builder(
        builder: (context) {
          // The dropdown is painted on the button's own background, so its
          // label and arrow take the button's foreground — whatever the theme
          // resolved for it — instead of a hardcoded color that only happens
          // to work on one surface.
          final onButton =
              DefaultTextStyle.of(context).style.color ?? colors.onPrimary;

          return DropdownButton<SongViewType>(
            borderRadius: BorderRadius.circular(15),
            isDense: true,
            padding: const EdgeInsets.only(top: 5, bottom: 5, left: 15, right: 5),
            underline: SizedBox.shrink(),
            focusColor: Colors.transparent,
            icon: Icon(Icons.arrow_drop_down_rounded, color: onButton),
            autofocus: false,
            value: selected,
            onChanged: (viewType) {
              if (viewType != null) onChanged(viewType);
            },
            // Menu entries sit on the menu's surface, not on the button.
            selectedItemBuilder: (context) => [
              for (final entry in entries)
                _ViewTypeLabel(entry: entry, color: onButton),
            ],
            items: [
              for (final entry in entries)
                DropdownMenuItem(
                  value: entry.type,
                  child: _ViewTypeLabel(entry: entry, color: colors.onSurface),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ViewTypeLabel extends StatelessWidget {
  const _ViewTypeLabel({required this.entry, required this.color});

  final ViewTypeEntry entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Icon(viewTypeIcon(entry.type), color: color),
        ),
        Text(entry.label, style: TextStyle(color: color)),
      ],
    );
  }
}
