import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/cue/slide.dart';
import '../../../data/song/song.dart';
import '../../../data/song/transpose.dart';
import '../../../services/app_links/navigation.dart';
import '../../../services/song/from_uuid.dart';
import '../../cue/cue_page_type.dart';
import '../../cue/session/cue_session.dart';
import '../../cue/session/session_provider.dart';
import '../../cue/widgets/slide_navigation_controls.dart';
import '../../cue/widgets/slide_list.dart';
import '../../song/cue_actions.dart';
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
            _ActiveCueCardSongAction(
              session: session,
              currentPath: currentPath,
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Lista kinyitása',
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
                onOpenCueEditor: () {
                  Navigator.of(sheetContext).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    context.push(
                      cueRoutePath(
                        session.cue.uuid,
                        CuePageType.edit,
                        slideUuid: session.currentSlideUuid,
                      ),
                    );
                  });
                },
                onClose: () => Navigator.of(sheetContext).pop(),
                showDragHandle: true,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActiveCueCardSongAction extends ConsumerWidget {
  const _ActiveCueCardSongAction({
    required this.session,
    required this.currentPath,
  });

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

    final songAlreadyInCue = session.slides.whereType<SongSlide>().any(
      (slide) => slide.song.uuid == currentSong.uuid,
    );

    if (songAlreadyInCue) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              size: 18,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 6),
            Text('Listában', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      );
    }

    final currentTranspose = ref.watch(transposeStateForProvider(currentSong));

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: _ActiveCueCardAddButton(
        session: session,
        currentSong: currentSong,
        currentTranspose: currentTranspose,
      ),
    );
  }
}

class _ActiveCueCardAddButton extends ConsumerStatefulWidget {
  const _ActiveCueCardAddButton({
    required this.session,
    required this.currentSong,
    required this.currentTranspose,
  });

  final CueSession session;
  final Song currentSong;
  final SongTranspose? currentTranspose;

  @override
  ConsumerState<_ActiveCueCardAddButton> createState() =>
      _ActiveCueCardAddButtonState();
}

class _ActiveCueCardAddButtonState
    extends ConsumerState<_ActiveCueCardAddButton> {
  bool _isAdding = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _isAdding ? null : _handleAddCurrentSong,
      icon: _isAdding
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add),
      label: const Text('Hozzáadás'),
    );
  }

  Future<void> _handleAddCurrentSong() async {
    if (_isAdding) return;

    setState(() => _isAdding = true);
    try {
      await addSongToActiveCue(
        ref: ref,
        song: widget.currentSong,
        transpose: widget.currentTranspose,
        session: widget.session,
      );
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
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
        padding: const EdgeInsets.fromLTRB(12, 15, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: railLabelStyle?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.list, size: 18, color: foregroundColor),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '$slideCount dia',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: railLabelStyle?.copyWith(
                            color: foregroundColor.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
    this.listVisible = true,
    this.onOpenCueEditor,
    this.onClose,
    this.showDragHandle = false,
    super.key,
  });

  final CueSession session;
  final bool listVisible;
  final VoidCallback? onOpenCueEditor;
  final VoidCallback? onClose;
  final bool showDragHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drawerBackgroundColor =
        theme.drawerTheme.backgroundColor ??
        theme.colorScheme.surfaceContainerLow;
    final appBarBackgroundColor =
        theme.appBarTheme.backgroundColor ??
        (theme.useMaterial3
            ? theme.colorScheme.surface
            : (theme.colorScheme.brightness == Brightness.dark
                  ? theme.colorScheme.surface
                  : theme.colorScheme.primary));

    return SizedBox.expand(
      child: Column(
        children: [
          if (showDragHandle)
            _CuePanelDragHandle(backgroundColor: appBarBackgroundColor),
          Expanded(
            child: Scaffold(
              backgroundColor: drawerBackgroundColor,
              appBar: _CuePanelAppBar(
                session: session,
                backgroundColor: appBarBackgroundColor,
                onClose: onClose,
                onOpenCueEditor:
                    onOpenCueEditor ??
                    () => _openCueEditor(
                      context,
                      slideUuid: session.currentSlideUuid,
                    ),
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SlideList(
                      isVisible: listVisible,
                      onSlideSelected: (slide) {
                        final ref = ProviderScope.containerOf(
                          context,
                          listen: false,
                        );
                        ref
                            .read(activeCueSessionProvider.notifier)
                            .goToSlide(slide.uuid);
                      },
                    ),
                  ),
                  const _CuePanelFooter(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openCueEditor(BuildContext context, {String? slideUuid}) {
    context.push(
      cueRoutePath(session.cue.uuid, CuePageType.edit, slideUuid: slideUuid),
    );
  }
}

class _CuePanelDragHandle extends StatelessWidget {
  const _CuePanelDragHandle({required this.backgroundColor});

  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _CuePanelAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _CuePanelAppBar({
    required this.session,
    required this.onOpenCueEditor,
    required this.backgroundColor,
    this.onClose,
  });

  final CueSession session;
  final VoidCallback onOpenCueEditor;
  final Color backgroundColor;
  final VoidCallback? onClose;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cueSubtitle = _cueSubtitleOf(session);
    final hasSubtitle = cueSubtitle.isNotEmpty;
    return AppBar(
      backgroundColor: backgroundColor,
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
      leading: const Icon(Icons.list),
      actions: [
        IconButton.filledTonal(
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
    );
  }
}

class _CuePanelFooter extends StatelessWidget {
  const _CuePanelFooter();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: const CueSlideNavigationControls(),
          ),
        ),
      ),
    );
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
