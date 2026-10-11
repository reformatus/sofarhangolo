import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wtf_sliding_sheet/wtf_sliding_sheet.dart';

import '../../services/app_links/navigation.dart';
import '../../services/song/song_content.dart';
import '../common/browser_title.dart';
import '../common/error/card.dart';
import 'widgets/content.dart';
import 'widgets/song_details_helpers.dart';

// TODO refactor into adaptive_page

class SongPage extends ConsumerStatefulWidget {
  const SongPage(this.songId, {super.key});
  final String songId;

  @override
  ConsumerState<SongPage> createState() => _SongPageState();
}

class _SongPageState extends ConsumerState<SongPage> {
  @override
  void initState() {
    detailsSheetScrollController = ScrollController();
    actionButtonsScrollController = ScrollController();
    transposeOverlayVisible = ValueNotifier<bool>(false);

    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRoute());
  }

  late final ScrollController detailsSheetScrollController;
  late final ScrollController actionButtonsScrollController;
  late final ValueNotifier<bool> transposeOverlayVisible;

  @override
  void didUpdateWidget(covariant SongPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncRoute());
    }
  }

  void _syncRoute() {
    if (!mounted) return;

    final targetRoute = songRoutePath(widget.songId);
    final currentRoute = GoRouterState.of(context).uri.toString();
    if (currentRoute == targetRoute) return;

    GoRouter.of(context).replace(targetRoute);
  }

  @override
  void dispose() {
    transposeOverlayVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songAsync = ref.watch(songContentProvider(widget.songId));

    if (songAsync.hasError && !songAsync.hasValue) {
      return _buildErrorCard(
        error: songAsync.error!,
        stackTrace: songAsync.stackTrace ?? StackTrace.empty,
      );
    }

    final snapshot = songAsync.value;
    if (!songAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot == null) {
      return _buildNotFoundCard();
    }

    final song = snapshot.song;
    return BrowserTitle(
      contextTitle: song.title,
      child: SongPageContent(
        song: song,
        detailsSheetScrollController: detailsSheetScrollController,
        actionButtonsScrollController: actionButtonsScrollController,
        transposeOverlayVisible: transposeOverlayVisible,
        onShowDetailsSheet: showDetailsBottomSheet,
      ),
    );
  }

  Widget _buildErrorCard({
    required Object error,
    required StackTrace stackTrace,
  }) {
    return Center(
      child: LErrorCard.fromError(
        error: error,
        stackTrace: stackTrace,
        title: 'Nem sikerült betölteni a dalt :(',
        icon: Icons.music_note,
      ),
    );
  }

  Widget _buildNotFoundCard() {
    return const Center(
      child: LErrorCard(
        type: LErrorType.info,
        title: 'Úgy tűnik, ez a dal nincs a táradban...',
        icon: Icons.search_off,
      ),
    );
  }

  Future<dynamic> showDetailsBottomSheet(
    BuildContext context,
    ScrollController detailsSheetScrollController,
    List<Widget> detailsContent,
  ) {
    return showSlidingBottomSheet(
      context,
      builder: (context) => SlidingSheetDialog(
        avoidStatusBar: true,
        maxWidth: 600,
        cornerRadius: 20,
        dismissOnBackdropTap: true,
        duration: Durations.medium2,
        headerBuilder: (context, state) {
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Row(
                  children: [
                    Text('Részletek', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        builder: (context, state) {
          // One selection area over the whole list so selections can span
          // detail items; the invisible line breaks keep copied text readable.
          return Material(
            child: SelectableDetailsList(children: detailsContent),
          );
        },
      ),
      useRootNavigator: false,
    );
  }
}
