import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sofarhangolo/ui/common/export_dialog/export_single_song_dialog.dart';

import '../../../data/song/song.dart';
import '../../../services/app_links/get_shareable.dart';
import '../../common/share/dialog.dart';
import '../view_chooser.dart';
import 'details_button.dart';

class SongPageAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const SongPageAppBar({
    super.key,
    required this.song,
    required this.isDesktop,
    required this.isMobile,
    required this.constraints,
    required this.summaryContent,
    required this.detailsContent,
    required this.onShowDetailsSheet,
    required this.detailsSheetScrollController,
  });

  final Song song;
  final bool isDesktop;
  final bool isMobile;
  final BoxConstraints constraints;
  final List<Widget> summaryContent;
  final List<Widget> detailsContent;
  final Function(BuildContext, ScrollController, List<Widget>)
  onShowDetailsSheet;
  final ScrollController detailsSheetScrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(song.title),
      actions: [
        if (isDesktop)
          ViewChooser(song: song, songSlide: null, useDropdown: false),
        if (detailsContent.isNotEmpty && !isDesktop && !isMobile) ...[
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2.5),
            child: DetailsButton(
              summaryContent: summaryContent,
              detailsContent: detailsContent,
              onShowDetailsSheet: onShowDetailsSheet,
              detailsSheetScrollController: detailsSheetScrollController,
            ),
          ),
        ],
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () => showShareDialog(
            context,
            title: 'Dal megosztása',
            description:
                'Mutasd meg a kódot vagy küldd el a linket valakinek. A megosztott ének megnyílik az eszközén.',
            sharedTitle: song.title,
            sharedLink: getShareableLinkFor(song),
            sharedIcon: Icons.music_note,
          ),
          icon: Icon(Icons.share),
          tooltip: 'Megosztási lehetőségek',
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () => showDialog(
            context: context,
            builder: (context) => ExportSingleSongDialog(song: song),
          ),
          icon: Icon(Icons.download),
          tooltip: 'Letöltés',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
