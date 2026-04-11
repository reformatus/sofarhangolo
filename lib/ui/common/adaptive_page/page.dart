import 'dart:async';
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
    this.leftDrawer,
    this.leftDrawerIcon,
    this.leftDrawerTooltip,
    this.rightDrawer,
    this.rightDrawerIcon,
    this.rightDrawerTooltip,
    this.actionBarChildren,
    this.actionBarTrailingChildren,
    this.bodyHeroTag,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leftDrawer;
  final IconData? leftDrawerIcon;
  final String? leftDrawerTooltip;
  final Widget? rightDrawer;
  final IconData? rightDrawerIcon;
  final String? rightDrawerTooltip;
  final List<Widget>? actionBarChildren;
  final List<Widget>? actionBarTrailingChildren;
  final Widget body;
  final String? bodyHeroTag;

  @override
  State<AdaptivePage> createState() => _AdaptivePageState();
}

class _AdaptivePageState extends State<AdaptivePage>
    with TickerProviderStateMixin {
  static const Duration _mobileIntroDelay = Duration(seconds: 1);

  late final AnimationController leftDrawerController;
  late final Animation<double> leftDrawerAnimation;
  late final AnimationController rightDrawerController;
  late final Animation<double> rightDrawerAnimation;
  late final AnimationStatusListener leftDrawerStatusListener;

  _AdaptivePageViewport? activeViewport;
  _AdaptivePageViewport? scheduledViewport;
  Timer? mobileIntroTimer;
  bool showMobileLeftPreview = false;
  bool hasHandledInitialMobileViewport = false;

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

    leftDrawerStatusListener = (status) {
      if (!mounted || status != AnimationStatus.dismissed) {
        return;
      }
      if (activeViewport != _AdaptivePageViewport.mobile ||
          !showMobileLeftPreview) {
        return;
      }

      setState(() {
        showMobileLeftPreview = false;
      });
    };
    leftDrawerController.addStatusListener(leftDrawerStatusListener);

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

    cancelMobileIntro();
    activeViewport = viewport;

    switch (viewport) {
      case _AdaptivePageViewport.mobile:
        applyMobileViewport(initial: initial);
      case _AdaptivePageViewport.tablet:
        showMobileLeftPreview = false;
        setDrawerOpen(
          leftDrawerController,
          open: widget.leftDrawer != null,
          animate: !initial,
        );
        setDrawerOpen(rightDrawerController, open: false, animate: !initial);
      case _AdaptivePageViewport.desktop:
        showMobileLeftPreview = false;
        setDrawerOpen(
          leftDrawerController,
          open: widget.leftDrawer != null,
          animate: !initial,
        );
        setDrawerOpen(
          rightDrawerController,
          open: widget.rightDrawer != null,
          animate: !initial,
        );
    }

    if (!initial && mounted) {
      setState(() {});
    }
  }

  void applyMobileViewport({required bool initial}) {
    final shouldShowIntro =
        initial &&
        !hasHandledInitialMobileViewport &&
        widget.leftDrawer != null;
    hasHandledInitialMobileViewport =
        hasHandledInitialMobileViewport || initial;

    if (shouldShowIntro) {
      showMobileLeftPreview = true;
      setDrawerOpen(leftDrawerController, open: true, animate: false);
      setDrawerOpen(rightDrawerController, open: false, animate: false);
      mobileIntroTimer = Timer(_mobileIntroDelay, () {
        if (!mounted ||
            activeViewport != _AdaptivePageViewport.mobile ||
            !showMobileLeftPreview) {
          return;
        }

        setDrawerOpen(leftDrawerController, open: false, animate: true);
      });
      return;
    }

    showMobileLeftPreview = false;
    setDrawerOpen(leftDrawerController, open: false, animate: false);
    setDrawerOpen(rightDrawerController, open: false, animate: false);
  }

  void cancelMobileIntro() {
    mobileIntroTimer?.cancel();
    mobileIntroTimer = null;
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

        if (activeViewport == null) {
          applyViewport(viewport, initial: true);
        } else if (activeViewport != viewport) {
          scheduleViewportSync(viewport);
        }

        return ClipRect(
          child: Scaffold(
            appBar: AppBar(
              title: widget.subtitle != null && widget.subtitle!.isNotEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context).appBarTheme.titleTextStyle,
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
                  : Text(widget.title),
              leading: BackButton(),
              automaticallyImplyLeading: false,
              actions: [
                SizedBox.shrink(),
                if (!tabletOrBigger) ...widget.actionBarTrailingChildren ?? [],
                SizedBox(width: 8),
              ],
            ),
            drawer: tabletOrBigger || widget.leftDrawer == null
                ? null
                : Drawer(child: SafeArea(child: widget.leftDrawer!)),
            endDrawer: tabletOrBigger || widget.rightDrawer == null
                ? null
                : Drawer(child: SafeArea(child: widget.rightDrawer!)),
            body: Builder(
              builder: (context) {
                return Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          if (widget.leftDrawer != null && tabletOrBigger)
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
                              children: [
                                if (!tabletOrBigger) _buildBody(),
                                Container(
                                  height: 50,
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      if (widget.leftDrawer != null)
                                        AdaptivePageDrawerButton(
                                          onPressed: tabletOrBigger
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
                                          child: Row(
                                            children: [
                                              ...widget.actionBarChildren ?? [],
                                              Spacer(),
                                              if (tabletOrBigger)
                                                ...widget
                                                        .actionBarTrailingChildren ??
                                                    [],
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (widget.rightDrawer != null)
                                        AdaptivePageDrawerButton(
                                          onPressed: tabletOrBigger
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

                          if (widget.rightDrawer != null && tabletOrBigger)
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
                      if (widget.leftDrawer != null &&
                          (tabletOrBigger || showMobileLeftPreview))
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
                      if (widget.rightDrawer != null && tabletOrBigger)
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
    cancelMobileIntro();
    leftDrawerController.removeStatusListener(leftDrawerStatusListener);
    leftDrawerController.dispose();
    rightDrawerController.dispose();
    super.dispose();
  }
}
