import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/bank/bank.dart';
import '../../../data/cue/slide.dart';
import '../../../data/song/song.dart';
import '../../../services/app_links/navigation.dart';
import '../../../services/songs/original_status.dart';
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

  /// Actions for the current song slide.
  ///
  /// A missing song is handled entirely by the centered slide view (single
  /// wording + its own remove action), so the drawer adds nothing there.
  List<Widget> _songSlideActions(
    BuildContext context,
    WidgetRef ref,
    SongSlide songSlide,
  ) {
    final liveSong = resolveLiveSong(ref, songSlide);

    if (liveSong == null) return const [];

    // Only warn about drift for changes the user did not make themselves.
    final changedByOther = songSlide.contentChangedByOthers(liveSong);

    // A bank song that already has a local copy can be swapped to it, keeping
    // the slide's own view/transpose settings.
    final localCopy = liveSong.sourceBank == localBankUuid
        ? null
        : ref.watch(localCopyForProvider(liveSong)).value;

    return [
      if (changedByOther) ...[
        const LErrorCard(
          type: LErrorType.info,
          title: 'Dal megváltozott',
          icon: Icons.edit_square,
          message: 'A dal tartalma megváltozott a listához adás óta.',
          showReportButton: false,
        ),
        const SizedBox(height: 8),
      ],
      if (localCopy != null) ...[
        const LErrorCard(
          type: LErrorType.info,
          title: 'Helyi másolat',
          icon: Icons.content_copy_outlined,
          message:
              'Ehhez a dalhoz készült szerkesztett helyi másolat, de a lista '
              'még a daltárbeli változatot használja.',
          showReportButton: false,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _useLocalCopy(songSlide, localCopy),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Csere a helyi másolatra'),
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

  /// Re-points the slide at [copy], keeping its view/transpose settings.
  void _useLocalCopy(SongSlide songSlide, Song copy) {
    ref
        .read(activeCueSessionProvider.notifier)
        .updateSlide(songSlide.retarget(copy));
  }
}
