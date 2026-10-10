import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/cue/slide.dart';
import '../../../services/app_links/navigation.dart';
import '../../common/error/card.dart';
import '../session/session_provider.dart';
import '../../song/transpose/widget.dart';
import '../../song/view_chooser.dart';
import '../slide_views/song.dart';

class ActionsDrawer extends ConsumerStatefulWidget {
  const ActionsDrawer({super.key});

  @override
  ConsumerState<ActionsDrawer> createState() => _ActionsDrawerState();
}

class _ActionsDrawerState extends ConsumerState<ActionsDrawer> {
  late final ScrollController scrollController;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
  }

  @override
  Widget build(BuildContext context) {
    final slide = ref.watch(currentSlideSnapshotProvider).slide;
    return FadingEdgeScrollView.fromSingleChildScrollView(
      child: SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...switch (slide) {
                null => const [],
                UnknownTypeSlide() => const [],
                SongSlide songSlide => _songSlideActions(context, ref, songSlide),
              },
            ],
          ),
        ),
      ),
    );
  }

  /// Actions for the current song slide. When the referenced song is missing,
  /// only an explanatory card and a remove action are offered.
  List<Widget> _songSlideActions(
    BuildContext context,
    WidgetRef ref,
    SongSlide songSlide,
  ) {
    final liveSong = resolveLiveSong(ref, songSlide);

    if (liveSong == null) {
      return [
        const LErrorCard(
          type: LErrorType.warning,
          title: 'A dal nem található',
          icon: Icons.music_off,
          message:
              'Ez a dal nincs meg ezen az eszközön. Eltávolíthatod a listából.',
          showReportButton: false,
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => ref
              .read(activeCueSessionProvider.notifier)
              .removeSlide(songSlide.uuid),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eltávolítás a listából'),
        ),
      ];
    }

    return [
      if (songSlide.contentDiffersFrom(liveSong)) ...[
        const LErrorCard(
          type: LErrorType.warning,
          title: 'Dal megváltozott',
          icon: Icons.edit_square,
          message: 'A dal tartalma megváltozott a listához adás óta.',
          showReportButton: false,
        ),
        const SizedBox(height: 8),
      ],
      ViewChooser(song: liveSong, songSlide: songSlide, useDropdown: true),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        onPressed: () => context.push(songRoutePath(liveSong.uuid)),
        label: const Text('Ugrás a dalhoz'),
        icon: const Icon(Icons.redo),
      ),
      const SizedBox(height: 8),
      TransposeCard(song: liveSong, songSlide: songSlide),
    ];
  }
}
