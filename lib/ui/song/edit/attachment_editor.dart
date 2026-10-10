import 'package:flutter/material.dart';

import '../../../data/song/extensions.dart';
import '../../../data/song/song.dart';
import '../sheet/view.dart';

/// Attachment surface (SVG/PDF) for the editor.
///
/// When the sheet is attached it renders the real asset with the song page's
/// [SheetView] (filling the whole page area); otherwise it is an empty-state
/// hint pointing at the action bar's attach button. The contextual
/// attach/replace/remove actions live in the page's action bar.
class AttachmentEditor extends StatelessWidget {
  const AttachmentEditor({super.key, required this.song, required this.isSvg});

  final Song song;
  final bool isSvg;

  @override
  Widget build(BuildContext context) {
    final attached = isSvg ? song.hasSvg : song.hasPdf;

    if (attached) {
      return isSvg ? SheetView.svg(song) : SheetView.pdf(song);
    }

    final colors = Theme.of(context).colorScheme;
    final icon = isSvg
        ? Icons.image_outlined
        : Icons.picture_as_pdf_outlined;

    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(icon, size: 64, color: colors.outline),
            Text(
              'Még nincs kotta csatolva.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.outline),
            ),
          ],
        ),
      ),
    );
  }
}
