import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/ui/common/export_dialog/export_util.dart';

class ExportSingleSongDialog extends ConsumerWidget {
  const ExportSingleSongDialog({required this.song, super.key});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final List<Widget> shareWidgets = [];
    if (song.contentMap['pdf'] != null) {
      shareWidgets.add(
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => getPDF(song, ref),
            child: const Text('PDF'),
          ),
        ),
      );
    }


    return AlertDialog(
      title: const Text('Dal letöltése'),
      scrollable: true,
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      backgroundColor: colorScheme.surfaceContainerHighest,
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                border: BoxBorder.fromLTRB(
                  top: BorderSide(
                    color: colorScheme.outline.withAlpha(60),
                    width: 1,
                  ),
                ),
              ),
              child: Column(spacing: 20, children: shareWidgets),
            ),
          ],
        ),
      ),
    );
  }
}
