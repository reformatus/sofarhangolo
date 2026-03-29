import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wtf_sliding_sheet/wtf_sliding_sheet.dart';

import '../../data/song/song.dart';
import '../../services/app_links/navigation.dart';
import '../../services/song/from_uuid.dart';
import '../common/error/card.dart';
import 'widgets/content.dart';

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
    final song = ref.watch(songFromUuidProvider(widget.songId));

    return switch (song) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error, :final stackTrace) => _buildErrorCard(
        error: error,
        stackTrace: stackTrace,
      ),
      AsyncValue(value: null) => _buildNotFoundCard(),
      AsyncValue(value: final Song song) => SongPageContent(
        song: song,
        detailsSheetScrollController: detailsSheetScrollController,
        actionButtonsScrollController: actionButtonsScrollController,
        transposeOverlayVisible: transposeOverlayVisible,
        onShowDetailsSheet: showDetailsBottomSheet,
      ),
    };
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
        headerBuilder: (context, state) => Padding(
          padding: const EdgeInsets.only(left: 16, right: 8, top: 8),
          child: Row(
            children: [
              Text('Részletek', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        builder: (context, state) {
          return Material(child: Column(children: detailsContent));
        },
      ),
      useRootNavigator: false,
    );
  }
}
