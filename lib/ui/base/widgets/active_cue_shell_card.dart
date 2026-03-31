import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/cue/slide.dart';
import '../../../services/app_links/navigation.dart';
import '../../cue/cue_page_type.dart';
import '../../cue/session/cue_session.dart';
import '../../cue/session/session_provider.dart';
import '../../cue/widgets/slide_list.dart';

const double cueShellOverlayReservedHeight = 84;

class ActiveCueShellCard extends ConsumerWidget {
  const ActiveCueShellCard({
    required this.session,
    required this.bottomOffset,
    this.contentLeftInset = 0,
    super.key,
  });

  final CueSession session;
  final double bottomOffset;
  final double contentLeftInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: contentLeftInset + 16,
        right: 16,
        bottom: bottomOffset + 12,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            elevation: 6,
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _openSheet(context, ref),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.view_list,
                              color: theme.colorScheme.primary,
                            ),
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
                                  Text(
                                    '${session.slideCount} elem',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Lista megnyitása',
                    onPressed: () => _openSheet(context, ref),
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: 'Aktív lista bezárása',
                    onPressed: () => _closeSession(ref),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _closeSession(WidgetRef ref) async {
    await ref.read(activeCueSessionProvider.notifier).unload();
  }

  Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final mediaQuery = MediaQuery.of(sheetContext);
        final maxWidth = mediaQuery.size.width >= 700 ? 620.0 : double.infinity;
        final targetHeight = math.min(mediaQuery.size.height * 0.78, 640.0);

        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  minHeight: 320,
                  maxHeight: targetHeight,
                ),
                child: Material(
                  clipBehavior: Clip.antiAlias,
                  color: Theme.of(sheetContext).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: Column(
                    children: [
                      _CueSheetHeader(
                        session: session,
                        onOpenCueEditor: () {
                          Navigator.of(sheetContext).pop();
                          context.go(
                            cueRoutePath(
                              session.cue.uuid,
                              CuePageType.edit,
                              slideUuid: ref.read(currentSlideUuidProvider),
                            ),
                          );
                        },
                        onCloseSession: () async {
                          Navigator.of(sheetContext).pop();
                          await _closeSession(ref);
                        },
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SlideList(
                          onSlideSelected: (slide) {
                            ref
                                .read(activeCueSessionProvider.notifier)
                                .goToSlide(slide.uuid);
                            Navigator.of(sheetContext).pop();

                            if (slide case SongSlide(:final song)) {
                              context.go(songRoutePath(song.uuid));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CueSheetHeader extends StatelessWidget {
  const _CueSheetHeader({
    required this.session,
    required this.onOpenCueEditor,
    required this.onCloseSession,
  });

  final CueSession session;
  final VoidCallback onOpenCueEditor;
  final VoidCallback onCloseSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Row(
            children: [
              Icon(Icons.view_list, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.cue.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '${session.slideCount} elem',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Lista szerkesztése',
                onPressed: onOpenCueEditor,
                icon: const Icon(Icons.open_in_full),
              ),
              IconButton(
                tooltip: 'Aktív lista bezárása',
                onPressed: onCloseSession,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
