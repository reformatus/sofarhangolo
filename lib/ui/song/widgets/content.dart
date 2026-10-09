import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/song/song.dart';
import '../../../data/song/song_fields.dart';
import '../../../config/config.dart';
import '../../../services/bank/banks.dart';
import '../../base/cue_shell_inset.dart';
import 'app_bar.dart';
import 'body.dart';
import 'song_details_helpers.dart';

class SongPageContent extends ConsumerWidget {
  const SongPageContent({
    super.key,
    required this.song,
    required this.detailsSheetScrollController,
    required this.actionButtonsScrollController,
    required this.transposeOverlayVisible,
    required this.onShowDetailsSheet,
  });

  final Song song;
  final ScrollController detailsSheetScrollController;
  final ScrollController actionButtonsScrollController;
  final ValueNotifier<bool> transposeOverlayVisible;
  final Function(BuildContext, ScrollController, List<Widget>)
  onShowDetailsSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop =
            (constraints.maxHeight < constraints.maxWidth) &&
            constraints.maxWidth > appConfig.breakpoints.desktopFromWidth;
        final isMobile = constraints.maxWidth < 400;
        final shellBottomInset = CueShellInset.bottomInsetOf(context);
        final showsBottomCueOverlay = CueShellInset.showsBottomOverlayOf(
          context,
        );

        // Bank overlay receptacle: fields the song's bank defines on top
        // of the shared vocabulary join the details list and the summary
        // chips (core fields immune).
        final bank = ref.watch(bankByUuidProvider(song.sourceBank));
        final detailsRegistry = bank == null
            ? defaultSongFieldRegistry
            : mergeSongFields(defaultSongFieldRegistry, bank.songFields);
        final summaryContent = getDetailsSummaryContent(
          song,
          context,
          detailsRegistry,
        );
        final detailsContent = getDetailsContent(
          song,
          context,
          detailsRegistry,
        );

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: SongPageAppBar(
            song: song,
            isDesktop: isDesktop,
            isMobile: isMobile,
            constraints: constraints,
            summaryContent: summaryContent,
            detailsContent: detailsContent,
            onShowDetailsSheet: onShowDetailsSheet,
            detailsSheetScrollController: detailsSheetScrollController,
          ),
          body: SongPageBody(
            song: song,
            isDesktop: isDesktop,
            showTabletCueAction: !isDesktop && !showsBottomCueOverlay,
            isMobile: isMobile,
            constraints: constraints,
            summaryContent: summaryContent,
            detailsContent: detailsContent,
            actionButtonsScrollController: actionButtonsScrollController,
            shellBottomInset: shellBottomInset,
            transposeOverlayVisible: transposeOverlayVisible,
            onShowDetailsSheet: onShowDetailsSheet,
            detailsSheetScrollController: detailsSheetScrollController,
          ),
        );
      },
    );
  }
}
