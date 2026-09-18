import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../services/app_links/navigation.dart';
import '../../../../services/ui/presentation_fullscreen.dart';
import '../../../common/browser_title.dart';
import '../../cue_page_type.dart';
import '../../session/cue_session.dart';
import '../../session/session_provider.dart';
import '../../widgets/slide_view.dart';

class CuePresentMusicianPage extends ConsumerStatefulWidget {
  const CuePresentMusicianPage(
    this.session, {
    this.fullscreenController,
    super.key,
  });

  final CueSession session;
  final PresentationFullscreenController? fullscreenController;

  @override
  ConsumerState<CuePresentMusicianPage> createState() =>
      _CuePresentMusicianPageState();
}

class _CuePresentMusicianPageState extends ConsumerState<CuePresentMusicianPage>
    with TickerProviderStateMixin {
  late final AnimationController overlayController;
  late final Animation<double> overlayAnimation;
  late final ProviderSubscription<String?> _slideListener;
  StreamSubscription<bool>? _fullscreenChanges;
  bool _awaitingExternalFullscreenExit = false;
  Timer? _overlayIntroShowTimer;
  Timer? _overlayIntroHideTimer;
  Timer? _overlayCloser;

  PresentationFullscreenController get _fullscreenController =>
      widget.fullscreenController ?? presentationFullscreenController;

  @override
  void initState() {
    overlayController = AnimationController(
      vsync: this,
      duration: Durations.long1,
      value: 0,
    );
    overlayAnimation = CurvedAnimation(
      parent: overlayController,
      curve: Curves.easeInOutCubicEmphasized,
      reverseCurve: Curves.easeInOutCubicEmphasized.flipped,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Wait for page transition before briefly showing the controls.
      _overlayIntroShowTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;

        overlayController.forward();
        _overlayIntroHideTimer = Timer(const Duration(milliseconds: 1000), () {
          if (!mounted) return;
          overlayController.reverse();
        });
      });
    });

    super.initState();
    _fullscreenChanges = _fullscreenController.changes.listen(
      _handleFullscreenChange,
    );
    _awaitingExternalFullscreenExit = _fullscreenController.isFullscreen;
    unawaited(_enterPresentationMode());

    _slideListener = ref.listenManual(
      currentSlideUuidProvider,
      fireImmediately: false,
      (_, slideUuid) => _syncRoute(slideUuid),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncRoute(ref.read(currentSlideUuidProvider)),
    );
  }

  @override
  void dispose() {
    _overlayIntroShowTimer?.cancel();
    _overlayIntroHideTimer?.cancel();
    _overlayCloser?.cancel();
    overlayController.dispose();
    _fullscreenChanges?.cancel();
    _slideListener.close();
    unawaited(_fullscreenController.exit());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CuePresentMusicianPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.cue.uuid != widget.session.cue.uuid) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncRoute(ref.read(currentSlideUuidProvider)),
      );
    }
  }

  void _syncRoute(String? slideUuid) {
    if (!mounted) return;

    final targetRoute = cueRoutePath(
      widget.session.cue.uuid,
      CuePageType.musician,
      slideUuid: slideUuid,
    );
    final currentRoute = GoRouterState.of(context).uri.toString();
    if (currentRoute == targetRoute) return;

    GoRouter.of(context).replace(targetRoute);
  }

  Future<void> _enterPresentationMode() async {
    await _fullscreenController.enter();
    if (!mounted) return;

    _awaitingExternalFullscreenExit = _fullscreenController.isFullscreen;
  }

  void _handleFullscreenChange(bool isFullscreen) {
    if (!_awaitingExternalFullscreenExit) {
      if (isFullscreen) {
        _awaitingExternalFullscreenExit = true;
      }
      return;
    }

    if (isFullscreen || !mounted) return;

    final slideUuid = ref.read(currentSlideUuidProvider);
    context.go(
      cueRoutePath(
        widget.session.cue.uuid,
        CuePageType.edit,
        slideUuid: slideUuid,
      ),
    );
  }

  void resetOverlayCloser() {
    _overlayCloser?.cancel();
    _overlayCloser = Timer(
      Duration(seconds: 3),
      () => overlayController.reverse(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slideIndex = ref.watch(slideIndexProvider);
    final canNavigatePrevious = ref.watch(canNavigatePreviousProvider);
    final canNavigateNext = ref.watch(canNavigateNextProvider);
    ref.watch(currentSlideUuidProvider);

    return BrowserTitle(
      contextTitle: widget.session.cue.title,
      child: Scaffold(
        body: SafeArea(
          child: ClipRect(
            child: AnimatedBuilder(
              animation: overlayAnimation,
              builder: (context, child) {
                return Stack(
                  children: [
                    child!,
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (_) {
                        if (overlayController.isCompleted) {
                          overlayController.reverse();
                        } else if (overlayController.isDismissed) {
                          overlayController.forward();
                          resetOverlayCloser();
                        }
                      },
                      onDoubleTap: () => context.pop(),
                      child: IgnorePointer(
                        child: SizedBox.expand(
                          child: Container(
                            color: Colors.black.withAlpha(
                              Tween<double>(
                                begin: 0,
                                end: 80,
                              ).animate(overlayAnimation).value.floor(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: FractionalTranslation(
                        translation: Offset(
                          0,
                          Tween<double>(
                            begin: -1.5,
                            end: 0,
                          ).animate(overlayAnimation).value,
                        ),
                        child: Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: FloatingActionButton(
                            onPressed: context.pop,
                            child: Icon(Icons.close),
                          ),
                        ),
                      ),
                    ),
                    if (canNavigatePrevious)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionalTranslation(
                          translation: Offset(
                            Tween<double>(
                              begin: -1.5,
                              end: 0,
                            ).animate(overlayAnimation).value,
                            0,
                          ),
                          child: SizedBox(
                            height: 90,
                            width: 50,
                            child: Material(
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  topRight: Radius.circular(10),
                                  bottomRight: Radius.circular(10),
                                ),
                              ),
                              elevation: 5,
                              child: InkWell(
                                onTap: () {
                                  ref
                                      .read(activeCueSessionProvider.notifier)
                                      .navigate(-1);
                                  resetOverlayCloser();
                                },
                                child: Center(
                                  child: Icon(Icons.chevron_left, size: 30),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (canNavigateNext)
                      Align(
                        alignment: Alignment.centerRight,
                        child: FractionalTranslation(
                          translation: Offset(
                            Tween<double>(
                              begin: 1.5,
                              end: 0,
                            ).animate(overlayAnimation).value,
                            0,
                          ),
                          child: SizedBox(
                            height: 90,
                            width: 50,
                            child: Material(
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(10),
                                  bottomLeft: Radius.circular(10),
                                ),
                              ),
                              elevation: 5,
                              child: InkWell(
                                onTap: () {
                                  ref
                                      .read(activeCueSessionProvider.notifier)
                                      .navigate(1);
                                  resetOverlayCloser();
                                },
                                child: Center(
                                  child: Icon(Icons.chevron_right, size: 30),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: FractionalTranslation(
                          translation: Offset(
                            0,
                            Tween<double>(
                              begin: 1.5,
                              end: 0,
                            ).animate(overlayAnimation).value,
                          ),
                          child: Card(
                            elevation: 5,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                '${(slideIndex?.index ?? 0) + 1} / ${slideIndex?.total}',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
              child: const SlideView(),
            ),
          ),
        ),
      ),
    );
  }
}
