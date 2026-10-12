import 'dart:math';

import 'package:flutter/material.dart';

import '../../../config/config.dart';
import 'drawer_button.dart';

enum _AdaptivePageViewport { mobile, tablet, desktop }

class AdaptivePage extends StatefulWidget {
  const AdaptivePage({
    required this.title,
    required this.body,
    this.subtitle,
    this.titleWidget,
    this.selectableTitle = false,
    this.leftDrawer,
    this.leftDrawerIcon,
    this.leftDrawerTooltip,
    this.rightDrawer,
    this.rightDrawerIcon,
    this.rightDrawerTooltip,
    this.actionBarChildren,
    this.appBarActions,
    this.bodyHeroTag,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Overrides [title] in the app bar with a custom widget, e.g. an
  /// editable title field. [subtitle] is not rendered when set.
  final Widget? titleWidget;

  /// Whether the app bar title (and subtitle) should be selectable. Enable
  /// for pages whose title is content-driven (e.g. cue titles), not for
  /// pages with static page names.
  final bool selectableTitle;
  final Widget? leftDrawer;
  final IconData? leftDrawerIcon;
  final String? leftDrawerTooltip;
  final Widget? rightDrawer;
  final IconData? rightDrawerIcon;
  final String? rightDrawerTooltip;
  final List<Widget>? actionBarChildren;
  final List<Widget>? appBarActions;
  final Widget body;
  final String? bodyHeroTag;

  @override
  State<AdaptivePage> createState() => _AdaptivePageState();
}

class _AdaptivePageState extends State<AdaptivePage>
    with TickerProviderStateMixin {
  late final AnimationController leftDrawerController;
  late final Animation<double> leftDrawerAnimation;
  late final AnimationController rightDrawerController;
  late final Animation<double> rightDrawerAnimation;

  _AdaptivePageViewport? activeViewport;
  _AdaptivePageViewport? scheduledViewport;

  @override
  void initState() {
    leftDrawerController = AnimationController(
      vsync: this,
      value: 0,
      duration: Durations.medium2,
    );

    rightDrawerController = AnimationController(
      vsync: this,
      value: 0,
      duration: Durations.medium2,
    );

    leftDrawerAnimation = CurvedAnimation(
      parent: leftDrawerController,
      curve: Curves.easeInOutCubicEmphasized,
      reverseCurve: Curves.easeInOutCubicEmphasized.flipped,
    );

    rightDrawerAnimation = CurvedAnimation(
      parent: rightDrawerController,
      curve: Curves.easeInOutCubicEmphasized,
      reverseCurve: Curves.easeInOutCubicEmphasized.flipped,
    );

    super.initState();
  }

  @override
  void didUpdateWidget(covariant AdaptivePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.leftDrawer == oldWidget.leftDrawer &&
        widget.rightDrawer == oldWidget.rightDrawer) {
      return;
    }

    final viewport = activeViewport;
    if (viewport == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || activeViewport != viewport) {
        return;
      }

      applyViewport(viewport);
    });
  }

  _AdaptivePageViewport viewportForWidth(double width) {
    if (width > appConfig.breakpoints.desktopFromWidth) {
      return _AdaptivePageViewport.desktop;
    }
    if (width > appConfig.breakpoints.tabletFromWidth) {
      return _AdaptivePageViewport.tablet;
    }
    return _AdaptivePageViewport.mobile;
  }

  double drawerWidthFor(BoxConstraints constraints) {
    return max(constraints.maxWidth / 5, 250);
  }

  /// Whether the left drawer is a persistent inline panel at [viewport].
  ///
  /// The left drawer is default-open on tablet and desktop; on mobile it is
  /// hidden and opened as a Scaffold overlay drawer.
  bool _leftDrawerDefaultsOpen(_AdaptivePageViewport viewport) {
    return viewport != _AdaptivePageViewport.mobile;
  }

  /// Whether the right drawer is a persistent inline panel at [viewport].
  ///
  /// The right drawer is only default-open on desktop; on mobile and tablet it
  /// is hidden and opened as a Scaffold overlay drawer.
  bool _rightDrawerDefaultsOpen(_AdaptivePageViewport viewport) {
    return viewport == _AdaptivePageViewport.desktop;
  }

  void scheduleViewportSync(_AdaptivePageViewport viewport) {
    if (scheduledViewport == viewport) {
      return;
    }

    scheduledViewport = viewport;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || scheduledViewport != viewport) {
        return;
      }

      scheduledViewport = null;
      applyViewport(viewport);
    });
  }

  void applyViewport(_AdaptivePageViewport viewport, {bool initial = false}) {
    if (!initial && activeViewport == viewport) {
      return;
    }

    activeViewport = viewport;

    // Only default-open drawers are rendered inline, so their controllers
    // track the persistent panel. Hidden drawers use the Scaffold overlay and
    // keep their inline controller closed.
    setDrawerOpen(
      leftDrawerController,
      open: widget.leftDrawer != null && _leftDrawerDefaultsOpen(viewport),
      animate: !initial,
    );
    setDrawerOpen(
      rightDrawerController,
      open: widget.rightDrawer != null && _rightDrawerDefaultsOpen(viewport),
      animate: !initial,
    );

    if (!initial && mounted) {
      setState(() {});
    }
  }

  void setDrawerOpen(
    AnimationController controller, {
    required bool open,
    required bool animate,
  }) {
    const epsilon = 0.001;

    if (open) {
      if (controller.status == AnimationStatus.forward ||
          controller.value >= 1 - epsilon) {
        return;
      }

      if (animate) {
        controller.forward();
      } else {
        controller.value = 1;
      }
      return;
    }

    if (controller.status == AnimationStatus.reverse ||
        controller.value <= epsilon) {
      return;
    }

    if (animate) {
      controller.reverse();
    } else {
      controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = viewportForWidth(constraints.maxWidth);
        final tabletOrBigger = viewport != _AdaptivePageViewport.mobile;
        final drawerWidth = drawerWidthFor(constraints);

        // A drawer is either a persistent inline panel (default-open at this
        // viewport) or fully hidden and opened through the Scaffold's overlay
        // drawer/endDrawer. There is no off-screen inline in-between state.
        final leftInline =
            widget.leftDrawer != null && _leftDrawerDefaultsOpen(viewport);
        final rightInline =
            widget.rightDrawer != null && _rightDrawerDefaultsOpen(viewport);
        final leftOverlay = widget.leftDrawer != null && !leftInline;
        final rightOverlay = widget.rightDrawer != null && !rightInline;

        if (activeViewport == null) {
          applyViewport(viewport, initial: true);
        } else if (activeViewport != viewport) {
          scheduleViewportSync(viewport);
        }

        return ClipRect(
          child: Scaffold(
            appBar: AppBar(
              title: Builder(
                builder: (context) {
                  if (widget.titleWidget != null) {
                    return widget.titleWidget!;
                  }
                  final Widget title =
                      widget.subtitle != null && widget.subtitle!.isNotEmpty
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: Theme.of(
                                context,
                              ).appBarTheme.titleTextStyle,
                            ),
                            Text(
                              widget.subtitle!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .appBarTheme
                                        .foregroundColor
                                        ?.withValues(alpha: 0.7),
                                  ),
                            ),
                          ],
                        )
                      : Text(widget.title);
                  if (!widget.selectableTitle) return title;
                  return SelectionArea(child: title);
                },
              ),
              leading: BackButton(),
              automaticallyImplyLeading: false,
              actions: [
                SizedBox.shrink(),
                ...widget.appBarActions ?? [],
                SizedBox(width: 8),
              ],
            ),
            drawer: leftOverlay
                ? Drawer(child: SafeArea(child: widget.leftDrawer!))
                : null,
            endDrawer: rightOverlay
                ? Drawer(child: SafeArea(child: widget.rightDrawer!))
                : null,
            body: Builder(
              builder: (context) {
                return Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          if (leftInline)
                            AnimatedBuilder(
                              animation: leftDrawerAnimation,
                              builder: (context, _) {
                                return SizedBox(
                                  width:
                                      drawerWidth * leftDrawerAnimation.value,
                                );
                              },
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!tabletOrBigger) _buildBody(),
                                Container(
                                  // No fixed height: the bar sizes to its
                                  // controls so they keep their natural
                                  // (Material 48px) height instead of being
                                  // squeezed into a set strip.
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      if (widget.leftDrawer != null)
                                        AdaptivePageDrawerButton(
                                          onPressed: leftInline
                                              ? leftDrawerController.toggle
                                              : Scaffold.of(context).openDrawer,
                                          animation: leftDrawerAnimation,
                                          drawerIcon: widget.leftDrawerIcon,
                                          tooltip: widget.leftDrawerTooltip,
                                        ),
                                      Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 5,
                                          ),
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children:
                                                  widget.actionBarChildren ??
                                                  const <Widget>[],
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (widget.rightDrawer != null)
                                        AdaptivePageDrawerButton(
                                          onPressed: rightInline
                                              ? rightDrawerController.toggle
                                              : Scaffold.of(
                                                  context,
                                                ).openEndDrawer,
                                          animation: rightDrawerAnimation,
                                          drawerIcon: widget.rightDrawerIcon,
                                          tooltip: widget.rightDrawerTooltip,
                                          endDrawer: true,
                                        ),
                                    ],
                                  ),
                                ),
                                if (tabletOrBigger) _buildBody(),
                              ],
                            ),
                          ),

                          if (rightInline)
                            AnimatedBuilder(
                              animation: rightDrawerAnimation,
                              builder: (context, _) {
                                return SizedBox(
                                  width:
                                      drawerWidth * rightDrawerAnimation.value,
                                );
                              },
                            ),
                        ],
                      ),
                      if (leftInline)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedBuilder(
                            animation: leftDrawerAnimation,
                            builder: (context, _) {
                              return FractionalTranslation(
                                translation: Tween<Offset>(
                                  begin: Offset(-1, 0),
                                  end: Offset.zero,
                                ).animate(leftDrawerAnimation).value,
                                child: SizedBox(
                                  width: drawerWidth,
                                  child: Drawer(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.only(
                                        topRight: Radius.circular(15),
                                      ),
                                    ),
                                    child: widget.leftDrawer,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      if (rightInline)
                        Align(
                          alignment: Alignment.centerRight,
                          child: AnimatedBuilder(
                            animation: rightDrawerAnimation,
                            builder: (context, _) {
                              return FractionalTranslation(
                                translation: Tween<Offset>(
                                  begin: Offset(1, 0),
                                  end: Offset.zero,
                                ).animate(rightDrawerAnimation).value,
                                child: SizedBox(
                                  width: drawerWidth,
                                  child: Drawer(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(15),
                                      ),
                                    ),
                                    child: widget.rightDrawer,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Expanded _buildBody() {
    return Expanded(
      child: widget.bodyHeroTag != null
          ? Hero(tag: widget.bodyHeroTag!, child: widget.body)
          : widget.body,
    );
  }

  @override
  void dispose() {
    leftDrawerController.dispose();
    rightDrawerController.dispose();
    super.dispose();
  }
}
