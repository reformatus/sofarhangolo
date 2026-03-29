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
                null => [],
                UnknownTypeSlide() => [],
                SongSlide() => [
                  if (slide.contentDifferentFlag) ...[
                    LErrorCard(
                      type: LErrorType.warning,
                      title: 'Dal megváltozott',
                      icon: Icons.edit_square,
                      message:
                          'A dal tartalma megváltozott a listához adás óta.',
                      showReportButton: false,
                    ),
                    SizedBox(height: 8),
                  ],
                  ViewChooser(
                    song: slide.song,
                    songSlide: slide,
                    useDropdown: true,
                  ),
                  SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        context.push(songRoutePath(slide.song.uuid)),
                    label: Text('Ugrás a dalhoz'),
                    icon: Icon(Icons.redo),
                  ),
                  SizedBox(height: 8),
                  TransposeCard(song: slide.song, songSlide: slide),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }
}
