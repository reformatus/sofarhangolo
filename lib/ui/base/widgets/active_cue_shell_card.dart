import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/cue/slide.dart';
import '../../../data/log/logger.dart';
import '../../../data/song/song.dart';
import '../../../data/song/transpose.dart';
import '../../../services/app_links/navigation.dart';
import '../../../services/song/from_uuid.dart';
import '../../../services/ui/messenger_service.dart';
import '../../cue/cue_page_type.dart';
import '../../cue/session/cue_session.dart';
import '../../cue/session/session_provider.dart';
import '../../cue/widgets/slide_list.dart';
import '../../song/state.dart';
import '../../song/transpose/state.dart';

const double cueShellOverlayReservedHeight = 56;

class ActiveCueShellCard extends StatelessWidget {
  const ActiveCueShellCard({
    required this.session,
    required this.currentPath,
    super.key,
  });

  final CueSession session;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cueSubtitle = _cueSubtitleOf(session);

    return Material(
      elevation: 0,
      shadowColor: Colors.transparent,
      color: theme.colorScheme.surfaceContainer,
      child: SizedBox(
        height: cueShellOverlayReservedHeight,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _openSheet(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.list, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.cue.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            if (cueSubtitle.isNotEmpty)
                              Text(
                                cueSubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${session.slideCount} dia',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Lista megnyitása',
              onPressed: () => _openSheet(context),
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: false,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final mediaQuery = MediaQuery.of(sheetContext);
        final maxWidth = mediaQuery.size.width >= 700 ? 620.0 : double.infinity;
        final targetHeight = math.min(mediaQuery.size.height * 0.78, 640.0);

        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              minHeight: 320,
              maxHeight: targetHeight,
            ),
            child: Material(
              clipBehavior: Clip.antiAlias,
              color: Theme.of(sheetContext).colorScheme.surfaceContainer,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: CueShellPanel(
                session: session,
                currentPath: currentPath,
                onClose: () => Navigator.of(sheetContext).pop(),
                onAfterSlideSelected: () => Navigator.of(sheetContext).pop(),
                showDragHandle: true,
              ),
            ),
          ),
        );
      },
    );
  }
}

class ActiveCueSidebarIndicator extends StatelessWidget {
  const ActiveCueSidebarIndicator({
    required this.session,
    required this.extendedRail,
    required this.listVisible,
    required this.onToggleList,
    required this.attachedColor,
    super.key,
  });

  final CueSession session;
  final bool extendedRail;
  final bool listVisible;
  final VoidCallback onToggleList;
  final Color attachedColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pillColor = listVisible
        ? attachedColor
        : _selectedDestinationPillColor(theme);
    final fgColor = listVisible
        ? scheme.onSurface
        : theme.navigationBarTheme.labelTextStyle?.resolve({
                WidgetState.selected,
              })?.color ??
              scheme.onSecondaryContainer;
    final radius = BorderRadius.horizontal(
      left: const Radius.circular(24),
      right: Radius.circular(listVisible ? 0 : 24),
    );

    return AnimatedContainer(
      duration: Durations.medium2,
      curve: Curves.easeInOutCubicEmphasized,
      decoration: BoxDecoration(color: pillColor, borderRadius: radius),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: extendedRail
            ? _ExpandedIndicator(
                title: session.cue.title,
                slideCount: session.slideCount,
                foregroundColor: fgColor,
                onToggleList: onToggleList,
                listVisible: listVisible,
              )
            : Tooltip(
                message: session.cue.title,
                child: _CollapsedIndicator(
                  foregroundColor: fgColor,
                  onToggleList: onToggleList,
                  listVisible: listVisible,
                ),
              ),
      ),
    );
  }
}

class _ExpandedIndicator extends StatelessWidget {
  const _ExpandedIndicator({
    required this.title,
    required this.slideCount,
    required this.foregroundColor,
    required this.onToggleList,
    required this.listVisible,
  });

  final String title;
  final int slideCount;
  final Color foregroundColor;
  final VoidCallback onToggleList;
  final bool listVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final railLabelStyle =
        theme.navigationRailTheme.unselectedLabelTextStyle ??
        theme.textTheme.labelMedium;

    return InkWell(
      onTap: onToggleList,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: railLabelStyle?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.list, size: 18, color: foregroundColor),
                const SizedBox(width: 6),
                Text(
                  '$slideCount dia',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: railLabelStyle?.copyWith(
                    color: foregroundColor.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: listVisible
                      ? 'Lista összecsukása'
                      : 'Lista kinyitása',
                  onPressed: onToggleList,
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    minimumSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                  ),
                  icon: Icon(
                    listVisible ? Icons.chevron_left : Icons.chevron_right,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapsedIndicator extends StatelessWidget {
  const _CollapsedIndicator({
    required this.foregroundColor,
    required this.onToggleList,
    required this.listVisible,
  });

  final Color foregroundColor;
  final VoidCallback onToggleList;
  final bool listVisible;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggleList,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: Icon(Icons.list, color: foregroundColor, size: 26),
            ),
            IconButton(
              tooltip: listVisible ? 'Lista összecsukása' : 'Lista kinyitása',
              onPressed: onToggleList,
              icon: Icon(
                listVisible ? Icons.chevron_left : Icons.chevron_right,
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CueShellPanel extends StatelessWidget {
  const CueShellPanel({
    required this.session,
    required this.currentPath,
    this.onClose,
    this.onAfterSlideSelected,
    this.showDragHandle = false,
    super.key,
  });

  final CueSession session;
  final String currentPath;
  final VoidCallback? onClose;
  final VoidCallback? onAfterSlideSelected;
  final bool showDragHandle;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: double.infinity,
      shape: const RoundedRectangleBorder(),
      child: Column(
        children: [
          _CuePanelHeader(
            session: session,
            onClose: onClose,
            showDragHandle: showDragHandle,
            onOpenCueEditor: () =>
                _openCueEditor(context, slideUuid: session.currentSlideUuid),
          ),
          Expanded(
            child: SlideList(
              onSlideSelected: (slide) {
                final ref = ProviderScope.containerOf(context, listen: false);
                ref
                    .read(activeCueSessionProvider.notifier)
                    .goToSlide(slide.uuid);
                _openCueEditor(context, slideUuid: slide.uuid);
                onAfterSlideSelected?.call();
              },
            ),
          ),
          _CuePanelSongAction(session: session, currentPath: currentPath),
        ],
      ),
    );
  }

  void _openCueEditor(BuildContext context, {String? slideUuid}) {
    context.go(
      cueRoutePath(session.cue.uuid, CuePageType.edit, slideUuid: slideUuid),
    );
  }
}

class _CuePanelHeader extends StatelessWidget {
  const _CuePanelHeader({
    required this.session,
    required this.onOpenCueEditor,
    this.onClose,
    this.showDragHandle = false,
  });

  final CueSession session;
  final VoidCallback onOpenCueEditor;
  final VoidCallback? onClose;
  final bool showDragHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cueSubtitle = _cueSubtitleOf(session);
    final hasSubtitle = cueSubtitle.isNotEmpty;
    final appBarBackgroundColor =
        theme.appBarTheme.backgroundColor ??
        (theme.useMaterial3
            ? theme.colorScheme.surface
            : (theme.colorScheme.brightness == Brightness.dark
                  ? theme.colorScheme.surface
                  : theme.colorScheme.primary));
    final foregroundColor =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDragHandle)
          ColoredBox(
            color: appBarBackgroundColor,
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        AppBar(
          backgroundColor: appBarBackgroundColor,
          title: hasSubtitle
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.cue.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.appBarTheme.titleTextStyle,
                    ),
                    Text(
                      cueSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                )
              : Text(session.cue.title),
          automaticallyImplyLeading: false,
          leading: Icon(Icons.list),
          actions: [
            IconButton(
              tooltip: 'Lista szerkesztése',
              onPressed: onOpenCueEditor,
              icon: const Icon(Icons.open_in_new),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Bezárás',
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ],
    );
  }
}

class _CuePanelSongAction extends ConsumerWidget {
  const _CuePanelSongAction({required this.session, required this.currentPath});

  final CueSession session;
  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSongUuid = _songUuidFromPath(currentPath);
    if (currentSongUuid == null) {
      return const SizedBox.shrink();
    }

    final currentSong = ref.watch(songFromUuidProvider(currentSongUuid)).value;
    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    final currentSongAlreadyInCue = session.slides.whereType<SongSlide>().any(
      (slide) => slide.song.uuid == currentSong.uuid,
    );
    if (currentSongAlreadyInCue) {
      return const SizedBox.shrink();
    }

    final currentTranspose = ref.watch(transposeStateForProvider(currentSong));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Align(
        alignment: Alignment.bottomRight,
        child: _CuePanelAddCurrentSongButton(
          session: session,
          currentSong: currentSong,
          currentTranspose: currentTranspose,
        ),
      ),
    );
  }
}

class _CuePanelAddCurrentSongButton extends ConsumerStatefulWidget {
  const _CuePanelAddCurrentSongButton({
    required this.session,
    required this.currentSong,
    required this.currentTranspose,
  });

  final CueSession session;
  final Song currentSong;
  final SongTranspose? currentTranspose;

  @override
  ConsumerState<_CuePanelAddCurrentSongButton> createState() =>
      _CuePanelAddCurrentSongButtonState();
}

class _CuePanelAddCurrentSongButtonState
    extends ConsumerState<_CuePanelAddCurrentSongButton> {
  bool _isAddingCurrentSong = false;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      tooltip: 'Dal hozzáadása listához',
      onPressed: _isAddingCurrentSong ? null : _handleAddCurrentSong,
      icon: _isAddingCurrentSong
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add),
      label: const Text('Hozzáadás'),
    );
  }

  Future<void> _handleAddCurrentSong() async {
    if (_isAddingCurrentSong) {
      return;
    }

    setState(() => _isAddingCurrentSong = true);
    try {
      final currentViewType = await ref.read(
        viewTypeForProvider(widget.currentSong, null).future,
      );

      ref
          .read(activeCueSessionProvider.notifier)
          .addSlide(
            SongSlide.from(
              widget.currentSong,
              viewType: currentViewType,
              transpose: widget.currentTranspose,
            ),
          );

      messengerService.showSnackBarReplacingCurrent(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            '${widget.currentSong.title} hozzáadva a listához: ${widget.session.cue.title}',
          ),
          duration: const Duration(seconds: 4),
        ),
        forceHideAfter: const Duration(seconds: 4),
      );
    } catch (e, s) {
      log.severe(
        'Nem sikerült alapértelmezett nézetet betölteni gyors hozzáadáshoz: ${widget.currentSong.uuid}',
        e,
        s,
      );
      messengerService.showSnackBarReplacingCurrent(
        const SnackBar(
          showCloseIcon: true,
          content: Text('Nem sikerült hozzáadni dalt a listához.'),
          duration: Duration(seconds: 4),
        ),
        forceHideAfter: const Duration(seconds: 4),
      );
    } finally {
      if (mounted) {
        setState(() => _isAddingCurrentSong = false);
      }
    }
  }
}

Color _selectedDestinationPillColor(ThemeData theme) =>
    theme.navigationBarTheme.indicatorColor ??
    theme.navigationRailTheme.indicatorColor ??
    theme.colorScheme.secondaryContainer;

String _cueSubtitleOf(CueSession session) =>
    session.cue.description.split('\n').first.trim();

String? _songUuidFromPath(String path) {
  final segments = Uri.parse(path).pathSegments;
  if (segments.length >= 2 && segments.first == 'song') {
    return segments[1];
  }
  return null;
}
