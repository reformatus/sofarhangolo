import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/app_links/get_shareable.dart';
import '../../../services/app_links/navigation.dart';
import '../../../services/songs/bundle/export_bundle.dart';
import '../../../services/songs/bundle/song_bundle.dart';
import '../../../services/ui/presentation_fullscreen.dart';
import '../../common/adaptive_page/page.dart';
import '../../common/browser_title.dart';
import '../../common/share/dialog.dart';
import '../cue_page_type.dart';
import '../session/cue_session.dart';
import '../session/session_provider.dart';
import '../widgets/actions_drawer.dart';
import '../widgets/add_slide_actions.dart';
import '../widgets/slide_navigation_controls.dart';
import '../widgets/slide_list.dart';
import '../widgets/slide_view.dart';

class CueEditPage extends ConsumerStatefulWidget {
  const CueEditPage(this.session, {super.key});

  final CueSession session;

  @override
  ConsumerState<CueEditPage> createState() => _CueEditPageState();
}

class _CueEditPageState extends ConsumerState<CueEditPage> {
  late final ProviderSubscription<String?> _slideListener;

  @override
  void initState() {
    super.initState();
    _slideListener = ref.listenManual(
      currentSlideUuidProvider,
      fireImmediately: false,
      (_, slideUuid) => _syncRoute(slideUuid),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncRoute(ref.read(currentSlideUuidProvider)),
    );
  }

  void _syncRoute(String? slideUuid) {
    if (!mounted) return;

    final targetRoute = cueRoutePath(
      widget.session.cue.uuid,
      CuePageType.edit,
      slideUuid: slideUuid,
    );
    final currentRoute = GoRouterState.of(context).uri.toString();
    if (currentRoute == targetRoute) return;

    GoRouter.of(context).replace(targetRoute);
  }

  @override
  void dispose() {
    _slideListener.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CueEditPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.cue.uuid != widget.session.cue.uuid) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncRoute(ref.read(currentSlideUuidProvider)),
      );
    }
  }

  /// Link share; when the cue has local songs (which a link cannot carry)
  /// the dialog also offers the cue and those songs as a file.
  Future<void> _share() async {
    final cue = widget.session.cue;
    final localSongs = await cueLocalSongUuids(cue);
    if (!mounted) return;
    await showShareDialog(
      context,
      title: 'Lista megosztása',
      description: 'Mutasd meg a kódot vagy küldd el a linket valakinek. A megosztott lista a listái közé kerül (vagy frissül, ha korábban már megnyitotta).',
      sharedTitle: cue.title,
      sharedDescription: cue.description.isEmpty ? null : cue.description,
      sharedLink: getShareableLinkFor(cue),
      sharedIcon: Icons.list,
      fileShare: localSongs.isEmpty
          ? null
          : ShareFileOption(
              fileName: songBundleFileName(cue.title),
              note:
                  'A listában ${localSongs.length} helyi dal van, ezeket a link nem viszi át. A fájl a listát és a helyi dalokat is tartalmazza.',
              build: () => exportSongBundle(const [], cue: cue),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BrowserTitle(
      contextTitle: widget.session.cue.title,
      child: AdaptivePage(
        title: widget.session.cue.title,
        selectableTitle: true,
        subtitle: widget.session.cue.description.isNotEmpty
            ? widget.session.cue.description
            : null,
        body: const SlideView(),
        leftDrawer: const SlideList(footer: CueAddSlideActions()),
        leftDrawerIcon: Icons.list,
        leftDrawerTooltip: 'Lista',
        rightDrawer: const ActionsDrawer(),
        rightDrawerIcon: Icons.more_vert,
        rightDrawerTooltip: 'Opciók',
        actionBarChildren: [
          const SizedBox(width: 8),
          const CueSlideNavigationControls(),
        ],
        appBarActions: [
          IconButton.filledTonal(
            onPressed: _share,
            icon: const Icon(Icons.share),
            tooltip: 'Megosztási lehetőségek',
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Teljes képernyő',
            onPressed: () async {
              await presentationFullscreenController.prepareForNavigation();
              if (!context.mounted) return;
              context.push(
                cueRoutePath(widget.session.cue.uuid, CuePageType.musician),
              );
            },
            icon: const Icon(Icons.fullscreen),
            color: Theme.of(context).colorScheme.onPrimary,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
