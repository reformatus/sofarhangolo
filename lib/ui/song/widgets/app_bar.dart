import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/bank/bank.dart';
import '../../../data/song/song.dart';
import '../../../services/app_links/get_shareable.dart';
import '../../../services/songs/bundle/export_bundle.dart';
import '../../../services/songs/bundle/song_bundle.dart';
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
    final isLocal = song.sourceBank == localBankUuid;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: SelectionArea(child: Text(song.title)),
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
            // A local song exists on this device only: a link or code would
            // open nothing for anyone else, so the song travels as a file.
            description: isLocal
                ? 'Ez a dal csak ezen az eszközön van meg, ezért linkkel nem küldhető el. Küldd el fájlként: a fogadó az Importálás fájlból paranccsal nyithatja meg.'
                : 'Mutasd meg a kódot vagy küldd el a linket valakinek. A megosztott ének megnyílik az eszközén.',
            sharedTitle: song.title,
            sharedLink: isLocal ? null : getShareableLinkFor(song),
            sharedIcon: Icons.music_note,
            song: song,
            fileShare: isLocal
                ? ShareFileOption(
                    fileName: songBundleFileName(song.title),
                    build: () => exportSongBundle([song.uuid]),
                  )
                : null,
          ),
          icon: Icon(Icons.share),
          tooltip: 'Megosztási lehetőségek',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
