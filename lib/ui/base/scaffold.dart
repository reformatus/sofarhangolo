import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../data/log/provider.dart';
import '../../services/app_links/app_links.dart';
import '../../services/app_version/check_new_version.dart';
import '../../services/connectivity/provider.dart';
import '../cue/session/session_provider.dart';
import 'cue_shell_inset.dart';
import 'widgets/active_cue_shell_card.dart';

typedef GeneralNavigationDestination = ({
  Widget icon,
  Widget? selectedIcon,
  String label,
});

NavigationDestination destinationFromGeneral(GeneralNavigationDestination d) =>
    NavigationDestination(
      icon: d.icon,
      selectedIcon: d.selectedIcon ?? d.icon,
      label: d.label,
    );

NavigationRailDestination railDestinationFromGeneral(
  GeneralNavigationDestination d,
) => NavigationRailDestination(
  icon: d.icon,
  selectedIcon: d.selectedIcon ?? d.icon,
  label: Text(d.label),
);

class BaseScaffold extends ConsumerStatefulWidget {
  const BaseScaffold({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<BaseScaffold> createState() => _BaseScaffoldState();

  static int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/home')) {
      return 0;
    }
    if (location.startsWith('/bank')) {
      return 1;
    }
    if (location.startsWith('/cues')) {
      return 2;
    }
    if (location.startsWith('/song')) {
      return 3;
    }
    if (location.startsWith('/cue')) {
      return 3;
    }
    return 0;
  }
}

class _BaseScaffoldState extends ConsumerState<BaseScaffold> {
  @override
  void initState() {
    super.initState();
    //extendedNavRail = MediaQuery.of(context).size.width > appConfig.breakpoints.desktopFromWidth;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        extendedNavRail =
            MediaQuery.of(context).size.width >
            appConfig.breakpoints.desktopFromWidth;
      });

      shouldNavigateListener = ref.listenManual(shouldNavigateProvider, (
        _,
        path,
      ) {
        final pathString = path.value;
        if (pathString != null) {
          final currentLocation = GoRouterState.of(context).uri.toString();
          if (currentLocation == pathString) return;
          GoRouter.of(context).go(pathString);
        }
      });
    });
  }

  @override
  void dispose() {
    shouldNavigateListener.close();
    super.dispose();
  }

  late ProviderSubscription shouldNavigateListener;

  bool extendedNavRail = true;

  @override
  Widget build(BuildContext context) {
    final newVersion = ref.watch(checkNewVersionProvider);
    final unreadLogCount = ref.watch(unreadLogCountProvider);
    final connection = ref.watch(connectionProvider);
    final activeCueSession = ref.watch(
      activeCueSessionProvider.select((sessionAsync) => sessionAsync.value),
    );
    final currentPath = GoRouterState.of(context).uri.path;
    final accessibleNavigation =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;

    final List<GeneralNavigationDestination> destinations = [
      (
        icon: Badge(
          isLabelVisible: (newVersion.value != null || unreadLogCount != 0),
          child: Icon(Icons.home_outlined),
        ),
        selectedIcon: Icon(Icons.home),
        label: 'Főoldal',
      ),
      (
        icon: Icon(Icons.library_music_outlined),
        selectedIcon: Icon(Icons.library_music),
        label: 'Dalok',
      ),
      (
        icon: Icon(Icons.view_list_outlined),
        selectedIcon: Icon(Icons.view_list),
        label: 'Listák',
      ),
      if (GoRouterState.of(context).uri.path.startsWith('/song/'))
        (
          icon: Icon(Icons.music_note_outlined),
          selectedIcon: Icon(Icons.music_note),
          label: 'Dal',
        ),
      if (GoRouterState.of(context).uri.path.startsWith('/cue/'))
        (
          icon: Icon(Icons.list),
          selectedIcon: Icon(Icons.list),
          label: 'Lista',
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // most songs are A4, this way we have the highest chance of fitting the song on the screen the biggest possible
        // TODO move this to global; take this into account on song page as well?
        bool showBottomNavBar =
            constraints.maxHeight / constraints.maxWidth > 1.41;
        final showCueOverlay =
            constraints.maxWidth < appConfig.breakpoints.desktopFromWidth &&
            _supportsCueOverlayForPath(currentPath) &&
            activeCueSession != null;
        final cueOverlayInset = showCueOverlay
            ? cueShellOverlayReservedHeight
            : 0.0;
        final shellFooterHeight = showBottomNavBar
            ? 65.0 + (connection == ConnectionType.offline ? 40 : 0)
            : 0.0;
        final cueOverlayBottomOffset = showBottomNavBar
            ? shellFooterHeight
            : 16.0;
        final cueOverlayLeftInset = showBottomNavBar
            ? 0.0
            : (extendedNavRail ? 150.0 : 70.0);
        final cueOverlayAnimationDuration = accessibleNavigation
            ? Duration.zero
            : Durations.medium2;
        final cueAwareChild = CueShellInset(
          bottomInset: cueOverlayInset,
          child: widget.child,
        );

        return Material(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: showBottomNavBar
                        ? MediaQuery.removePadding(
                            context: context,
                            removeBottom: true,
                            child: SafeArea(child: cueAwareChild),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainer,
                                child: SafeArea(
                                  right: false,
                                  top: false,
                                  bottom: false,
                                  child: AnimatedSize(
                                    clipBehavior: Clip.none,
                                    duration: Duration(milliseconds: 300),
                                    curve: Curves.easeInOutCubicEmphasized,
                                    child: SizedBox(
                                      width: extendedNavRail ? 150 : 70,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Align(
                                            alignment: Alignment.topRight,
                                            child: IntrinsicHeight(
                                              child: NavigationRail(
                                                extended: extendedNavRail,
                                                labelType: extendedNavRail
                                                    ? NavigationRailLabelType
                                                          .none
                                                    : NavigationRailLabelType
                                                          .selected,
                                                destinations: destinations
                                                    .map(
                                                      (d) =>
                                                          railDestinationFromGeneral(
                                                            d,
                                                          ),
                                                    )
                                                    .toList(),
                                                selectedIndex:
                                                    BaseScaffold._calculateSelectedIndex(
                                                      context,
                                                    ),
                                                onDestinationSelected:
                                                    (int index) =>
                                                        _onDestinationSelected(
                                                          index,
                                                          context,
                                                        ),
                                                backgroundColor:
                                                    Colors.transparent,
                                                minExtendedWidth: 160,
                                              ),
                                            ),
                                          ),
                                          Spacer(),
                                          if (connection ==
                                              ConnectionType.offline)
                                            Container(
                                              padding: EdgeInsets.all(7),
                                              margin: EdgeInsets.all(7),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withAlpha(
                                                  200,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.public_off_outlined,
                                                  ),
                                                  if (extendedNavRail)
                                                    Padding(
                                                      padding:
                                                          EdgeInsetsGeometry.only(
                                                            left: 5,
                                                          ),
                                                      child: Text('Offline'),
                                                    ),
                                                ],
                                              ),
                                            ),

                                          Padding(
                                            padding: EdgeInsets.all(8),
                                            child: Flex(
                                              direction: extendedNavRail
                                                  ? Axis.horizontal
                                                  : Axis.vertical,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                if (extendedNavRail) Spacer(),
                                                IconButton(
                                                  icon: Icon(
                                                    extendedNavRail
                                                        ? Icons.chevron_left
                                                        : Icons.chevron_right,
                                                  ),
                                                  tooltip: extendedNavRail
                                                      ? "Összecsukás"
                                                      : "Kinyitás",
                                                  onPressed: () {
                                                    setState(() {
                                                      extendedNavRail =
                                                          !extendedNavRail;
                                                    });
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // TODO validate on iOS!
                              Expanded(
                                child: MediaQuery.removePadding(
                                  removeLeft: true,
                                  context: context,
                                  child: SafeArea(child: cueAwareChild),
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (showBottomNavBar) ...[
                    Container(
                      color: Colors.red.withAlpha(200),
                      child: AnimatedSize(
                        duration: Durations.medium4,

                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            if (connection == ConnectionType.offline) ...[
                              Icon(Icons.public_off_outlined),
                              Padding(
                                padding: EdgeInsetsGeometry.only(
                                  left: 5,
                                  top: 8,
                                  bottom: 8,
                                ),
                                child: Text('Offline'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: NavigationBar(
                        labelBehavior:
                            NavigationDestinationLabelBehavior.onlyShowSelected,
                        height: 65,
                        destinations: destinations
                            .map((d) => destinationFromGeneral(d))
                            .toList(),
                        selectedIndex: BaseScaffold._calculateSelectedIndex(
                          context,
                        ),
                        onDestinationSelected: (int index) =>
                            _onDestinationSelected(index, context),
                      ),
                    ),
                  ],
                ],
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !showCueOverlay,
                  child: AnimatedSwitcher(
                    duration: cueOverlayAnimationDuration,
                    reverseDuration: cueOverlayAnimationDuration,
                    switchInCurve: Curves.easeInOutCubicEmphasized,
                    switchOutCurve: Curves.easeInOutCubicEmphasized.flipped,
                    transitionBuilder: (child, animation) {
                      final offsetAnimation = Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(animation);

                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: offsetAnimation,
                          child: child,
                        ),
                      );
                    },
                    child: showCueOverlay
                        ? ActiveCueShellCard(
                            key: ValueKey(
                              'cue-shell-card-${activeCueSession.cue.uuid}',
                            ),
                            session: activeCueSession,
                            bottomOffset: cueOverlayBottomOffset,
                            contentLeftInset: cueOverlayLeftInset,
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('cue-shell-card-empty'),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _supportsCueOverlayForPath(String path) {
    return path.startsWith('/bank') || path.startsWith('/song/');
  }

  void _onDestinationSelected(int index, BuildContext context) {
    switch (index) {
      case 0:
        GoRouter.of(context).go('/home');
      case 1:
        GoRouter.of(context).go('/bank');
      case 2:
        GoRouter.of(context).go('/cues');
      default:
        return;
    }
  }
}
