import 'package:flutter/material.dart';

import '../../../data/song/extensions.dart';
import '../../../data/song/song.dart';
import '../sheet/view.dart';
import '../state.dart';
import '../view_chooser.dart';

/// Attachment surface (SVG/PDF) for the editor.
///
/// When the sheet is attached it renders the real asset with the song page's
/// [SheetView] (filling the whole page area). Otherwise it is an empty state
/// whose icon matches the segmented view chooser and whose attach button takes
/// the place of the page's own attach action. Once attached, replace/remove
/// live in the page's action bar.
class AttachmentEditor extends StatelessWidget {
  const AttachmentEditor({
    super.key,
    required this.song,
    required this.isSvg,
    required this.onAttach,
  });

  final Song song;
  final bool isSvg;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final attached = isSvg ? song.hasSvg : song.hasPdf;

    if (attached) {
      return isSvg ? SheetView.svg(song) : SheetView.pdf(song);
    }

    final colors = Theme.of(context).colorScheme;
    final icon = viewTypeIcon(isSvg ? SongViewType.svg : SongViewType.pdf);

    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            Icon(icon, size: 64, color: colors.outline),
            FilledButton.icon(
              onPressed: onAttach,
              icon: const Icon(Icons.upload_file),
              label: const Text('Fájl csatolása'),
            ),
          ],
        ),
      ),
    );
  }
}
