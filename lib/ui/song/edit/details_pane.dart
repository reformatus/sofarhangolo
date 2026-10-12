import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/song/song.dart';
import '../../../services/songs/original_status.dart';
import '../../common/notice/card.dart';
import '../../common/sidebar/sidebar.dart';
import 'song_field_editors.dart';

/// Right-pane song details: the original bank song (for copies) and the
/// editable metadata fields.
class DetailsPane extends ConsumerWidget {
  const DetailsPane({
    super.key,
    required this.song,
    required this.contentMap,
    required this.keyField,
    required this.onFieldChanged,
    required this.onKeysChanged,
  });

  /// The (last saved) song, used by the original-song card.
  final Song song;

  /// The live draft metadata, so edits reflect immediately.
  final Map<String, Object> contentMap;
  final List<KeyField> keyField;

  /// Called with the new raw value for a `contentMap` field (null clears it).
  final void Function(String apiName, Object? value) onFieldChanged;

  /// Called when the song's keys change.
  final ValueChanged<List<KeyField>> onKeysChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // null for songs that are not a copy; `unchanged` is the copy whose bank
    // original is still exactly what the copy was made of.
    final originalStatus = ref.watch(originalSongStatusProvider(song)).value;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SidebarColumn(
        gap: 20,
        children: [
          // Only surface the original-song card when there is something to
          // report: the original changed since the copy was made, or it
          // vanished. An unchanged copy would otherwise show a permanent
          // "nothing to see here" box. The card is left out of the children
          // entirely (instead of building an empty box) so SidebarColumn's
          // spacing does not leave a stray gap where it used to be.
          if (originalStatus != null &&
              originalStatus != OriginalSongStatus.unchanged)
            _OriginalSongCard(song, originalStatus),
          for (final field in editableSongFields())
            if (songFieldEditorKind(field) == SongFieldEditorKind.key)
              SongKeyField(
                key: const ValueKey('song-field-key'),
                initialKeys: keyField,
                onChanged: onKeysChanged,
              )
            else
              SongContentFieldEditor(
                key: ValueKey('song-field-${field.apiName}'),
                field: field,
                value: contentMap[field.apiName],
                onChanged: (value) => onFieldChanged(field.apiName, value),
              ),
        ],
      ),
    );
  }
}

/// The notice about the bank song a local copy was made from.
///
/// [status] is only ever [OriginalSongStatus.changed] or
/// [OriginalSongStatus.missing]; [DetailsPane] decides whether to show the
/// card at all.
class _OriginalSongCard extends ConsumerWidget {
  const _OriginalSongCard(this.song, this.status);

  final Song song;
  final OriginalSongStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final original = ref.watch(originalSongProvider(song)).value;

    final (statusIcon, statusLabel, type) = switch (status) {
      OriginalSongStatus.unchanged => (
        Icons.check_circle_outline,
        'Nem változott.',
        LNoticeType.info,
      ),
      OriginalSongStatus.changed => (
        Icons.sync_problem_outlined,
        'Megváltozott a másolás óta.',
        LNoticeType.warning,
      ),
      OriginalSongStatus.missing => (
        Icons.link_off,
        'Az eredeti dal már nincs meg.',
        LNoticeType.warning,
      ),
    };

    return LNoticeCard(
      type: type,
      icon: statusIcon,
      title: 'Eredeti dal',
      message: [
        original?.title ?? 'Az eredeti dal nem elérhető',
        statusLabel,
      ].join('\n'),
      actions: [
        if (original != null)
          OutlinedButton.icon(
            onPressed: () => context.push('/song/${original.uuid}'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Eredeti megtekintése'),
          ),
      ],
    );
  }
}
