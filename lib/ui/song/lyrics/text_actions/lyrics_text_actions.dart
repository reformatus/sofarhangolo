import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../data/song/song.dart';
import 'lyrics_actions_menu.dart';
import 'lyrics_selection_dialog.dart';

/// Installs the lyrics text-action gestures on the lyrics surface background:
///
/// - touch long-press: context menu (whole-song scope)
/// - mouse/stylus click: selection dialog (whole-song scope)
/// - mouse/stylus right-click: context menu at pointer
/// - hover: text cursor
///
/// Verse cards install the same behaviors scoped to their own verse; this
/// widget only catches presses that land between the verse cards.
class LyricsTextActions extends StatelessWidget {
  const LyricsTextActions({
    required this.song,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Song song;
  final Widget child;

  /// Set to `false` to disable all text actions (e.g. the presenter view,
  /// where stray taps must not open dialogs).
  final bool enabled;

  void _openMenu(BuildContext context, Offset globalPosition) {
    showLyricsTextActionsMenu(context, song: song, position: globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) {
          // Only mouse clicks open the dialog; touch and stylus users get the
          // long-press context menu instead.
          if (details.kind == PointerDeviceKind.mouse) {
            showLyricsSelectionDialog(context, song: song);
          }
        },
        onSecondaryTapUp: (details) =>
            _openMenu(context, details.globalPosition),
        onLongPressStart: (details) =>
            _openMenu(context, details.globalPosition),
        child: child,
      ),
    );
  }
}
