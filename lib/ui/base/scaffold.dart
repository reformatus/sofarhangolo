import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../data/log/provider.dart';
import '../../services/app_links/app_links.dart';
import '../../services/app_version/check_new_version.dart';
import '../../services/connectivity/provider.dart';
import '../../services/app_links/navigation.dart';
import '../cue/cue_page_type.dart';
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
  final _contentScaffoldKey = GlobalKey<ScaffoldState>();
  bool _desktopCueListVisible = true;
  bool _desktopCueListSlotVisible = true;
  bool _tabletCueDrawerVisible = false;
  int _desktopCueListAnimationTick = 0;

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
        final theme = Theme.of(context);
        final isDesktop =
            constraints.maxWidth > appConfig.breakpoints.desktopFromWidth;
        // most songs are A4, this way we have the highest chance of fitting the song on the screen the biggest possible
        // TODO move this to global; take this into account on song page as well?
        bool showBottomNavBar =
            constraints.maxHeight / constraints.maxWidth > 1.41;
        final supportsCueOverlay = _supportsCueOverlayForPath(currentPath);
        final showCueOverlay =
            showBottomNavBar && supportsCueOverlay && activeCueSession != null;
        final showSidebarCueControls =
            !showBottomNavBar && supportsCueOverlay && activeCueSession != null;
        final usesCueDrawer = showSidebarCueControls && !isDesktop;
        final sidebarCueSession = showSidebarCueControls
            ? activeCueSession
            : null;
        final cuePanelColor = theme.colorScheme.surfaceContainerLow;
        final sidebarCueListVisible = isDesktop
            ? _desktopCueListVisible
            : _tabletCueDrawerVisible;
        final cuePanelWidth = math
            .max(constraints.maxWidth / 5, 250)
            .toDouble();
        const cueOverlayInset = 0.0;
        final cueOverlayAnimationDuration = accessibleNavigation
            ? Duration.zero
            : Durations.medium2;
        final showDesktopCueSidebar = showSidebarCueControls && isDesktop;
        final cueAwareChild = CueShellInset(
          bottomInset: cueOverlayInset,
          child: widget.child,
        );

        void toggleDesktopCueList() {
          if (_desktopCueListVisible) {
            final currentTick = ++_desktopCueListAnimationTick;
            setState(() {
              _desktopCueListVisible = false;
            });
            if (cueOverlayAnimationDuration == Duration.zero) {
              setState(() {
                _desktopCueListSlotVisible = false;
              });
              return;
            }
            Future<void>.delayed(cueOverlayAnimationDuration, () {
              if (!mounted) return;
              if (currentTick != _desktopCueListAnimationTick) return;
              if (_desktopCueListVisible) return;
              setState(() {
                _desktopCueListSlotVisible = false;
              });
            });
          } else {
            _desktopCueListAnimationTick++;
            setState(() {
              _desktopCueListSlotVisible = true;
              _desktopCueListVisible = true;
            });
          }
        }

        return Scaffold(
          body: Material(
            child: Column(
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
                              color: theme.colorScheme.surfaceContainer,
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
                                                  ? NavigationRailLabelType.none
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
                                        if (showSidebarCueControls)
                                          Padding(
                                            padding: EdgeInsets.fromLTRB(
                                              8,
                                              8,
                                              sidebarCueListVisible ? 0 : 8,
                                              8,
                                            ),
                                            child: ActiveCueSidebarIndicator(
                                              session: sidebarCueSession!,
                                              extendedRail: extendedNavRail,
                                              listVisible:
                                                  sidebarCueListVisible,
                                              onToggleList: () {
                                                if (isDesktop) {
                                                  toggleDesktopCueList();
                                                } else if (usesCueDrawer) {
                                                  if (_tabletCueDrawerVisible) {
                                                    Navigator.of(
                                                      context,
                                                    ).maybePop();
                                                  } else {
                                                    _contentScaffoldKey
                                                        .currentState
                                                        ?.openDrawer();
                                                  }
                                                }
                                              },
                                              attachedColor: cuePanelColor,
                                            ),
                                          ),
                                        Spacer(),
                                        if (connection ==
                                            ConnectionType.offline)
                                          Container(
                                            padding: EdgeInsets.all(7),
                                            margin: EdgeInsets.all(7),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withAlpha(200),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.public_off_outlined),
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
                                          child: extendedNavRail
                                              ? Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: IconButton(
                                                        icon: const Icon(
                                                          Icons.chevron_left,
                                                        ),
                                                        tooltip: "Összecsukás",
                                                        onPressed: () {
                                                          setState(() {
                                                            extendedNavRail =
                                                                false;
                                                          });
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Flex(
                                                  direction: Axis.vertical,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    const SizedBox(
                                                      width: 8,
                                                      height: 8,
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.chevron_right,
                                                      ),
                                                      tooltip: "Kinyitás",
                                                      onPressed: () {
                                                        setState(() {
                                                          extendedNavRail =
                                                              true;
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
                            if (showDesktopCueSidebar &&
                                (_desktopCueListVisible ||
                                    _desktopCueListSlotVisible))
                              SizedBox(
                                width: cuePanelWidth,
                                child: Material(
                                  key: const ValueKey('desktop-cue-sidebar'),
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  color: cuePanelColor,
                                  child: SafeArea(
                                    top: false,
                                    bottom: false,
                                    child: AnimatedSwitcher(
                                      duration: cueOverlayAnimationDuration,
                                      switchInCurve:
                                          Curves.easeInOutCubicEmphasized,
                                      switchOutCurve: Curves
                                          .easeInOutCubicEmphasized
                                          .flipped,
                                      transitionBuilder: (child, animation) {
                                        final offsetAnimation = Tween<Offset>(
                                          begin: const Offset(-0.08, 0),
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
                                      child: _desktopCueListVisible
                                          ? CueShellPanel(
                                              key: const ValueKey(
                                                'desktop-cue-sidebar-panel',
                                              ),
                                              session: sidebarCueSession!,
                                              currentPath: currentPath,
                                            )
                                          : const SizedBox.shrink(
                                              key: ValueKey(
                                                'desktop-cue-sidebar-hidden',
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: ClipRect(
                                child: Scaffold(
                                  key: _contentScaffoldKey,
                                  drawerEnableOpenDragGesture: usesCueDrawer,
                                  onDrawerChanged: (isOpened) {
                                    if (_tabletCueDrawerVisible != isOpened) {
                                      setState(
                                        () =>
                                            _tabletCueDrawerVisible = isOpened,
                                      );
                                    }
                                  },
                                  drawer: usesCueDrawer
                                      ? Drawer(
                                          width: cuePanelWidth,
                                          backgroundColor: cuePanelColor,
                                          elevation: 0,
                                          shape: const RoundedRectangleBorder(),
                                          child: SafeArea(
                                            top: false,
                                            bottom: false,
                                            child: CueShellPanel(
                                              session: sidebarCueSession!,
                                              currentPath: currentPath,
                                              onAfterSlideSelected: () {
                                                Navigator.of(
                                                  context,
                                                ).maybePop();
                                              },
                                            ),
                                          ),
                                        )
                                      : null,
                                  body: MediaQuery.removePadding(
                                    removeLeft: true,
                                    context: context,
                                    child: SafeArea(child: cueAwareChild),
                                  ),
                                ),
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
                  AnimatedSwitcher(
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
                            currentPath: currentPath,
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('cue-shell-card-empty'),
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
          ),
        );
      },
    );
  }

  bool _supportsCueOverlayForPath(String path) {
    return path.startsWith('/bank') || path.startsWith('/song/');
  }

  void _openCueEditor(BuildContext context, {required String cueUuid}) {
    GoRouter.of(context).go(
      cueRoutePath(
        cueUuid,
        CuePageType.edit,
        slideUuid: ref.read(currentSlideUuidProvider),
      ),
    );
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
