import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/app_links/get_shareable.dart';
import '../../../services/app_links/navigation.dart';
import '../../../services/ui/presentation_fullscreen.dart';
import '../../common/adaptive_page/page.dart';
import '../../common/browser_title.dart';
import '../../common/share/dialog.dart';
import '../cue_page_type.dart';
import '../session/cue_session.dart';
import '../session/session_provider.dart';
import '../widgets/actions_drawer.dart';
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

  @override
  Widget build(BuildContext context) {
    return BrowserTitle(
      contextTitle: widget.session.cue.title,
      child: AdaptivePage(
        title: widget.session.cue.title,
        subtitle: widget.session.cue.description.isNotEmpty
            ? widget.session.cue.description
            : null,
        body: const SlideView(),
        leftDrawer: const SlideList(),
        leftDrawerIcon: Icons.list,
        leftDrawerTooltip: 'Lista',
        rightDrawer: const ActionsDrawer(),
        rightDrawerIcon: Icons.more_vert,
        rightDrawerTooltip: 'Opciók',
        actionBarChildren: [
          const SizedBox(width: 8),
          const CueSlideNavigationControls(),
        ],
        actionBarTrailingChildren: [
          IconButton.filledTonal(
            onPressed: () => showShareDialog(
              context,
              title: 'Lista megosztása',
              description:
                  'Mutasd meg a kódot vagy küldd el a linket valakinek. A megosztott lista a listái közé kerül (vagy frissül, ha korábban már megnyitotta).',
              sharedTitle: widget.session.cue.title,
              sharedDescription: widget.session.cue.description.isEmpty
                  ? null
                  : widget.session.cue.description,
              sharedLink: getShareableLinkFor(widget.session.cue),
              sharedIcon: Icons.list,
            ),
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
