import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../data/song/lyrics/parser.dart';
import '../../../../data/song/song.dart';
import '../../../../services/text_export/song_lyrics.dart';
import '../../../../services/ui/messenger_service.dart';
import 'lyrics_selection_dialog.dart';

/// Actions offered by the lyrics context menu.
enum LyricsTextAction { selectText, copyVerse, copySong }

const _desktopPlatforms = {
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
};

/// Shows the lyrics text-actions context menu.
///
/// [verse] scopes the menu to a single verse (adds "Versszak másolása" and
/// preselects the verse in the selection dialog); pass `null` for a background
/// press (whole-song scope). On desktop [position] anchors a popup menu, on
/// touch platforms a bottom sheet is shown instead.
Future<void> showLyricsTextActionsMenu(
  BuildContext context, {
  required Song song,
  ParsedVerse? verse,
  int? verseIndex,
  Offset? position,
}) async {
  final entries = <(LyricsTextAction, String, IconData)>[
    (
      LyricsTextAction.selectText,
      'Szövegkijelölés…',
      Icons.select_all_outlined,
    ),
    if (verse != null)
      (LyricsTextAction.copyVerse, 'Versszak másolása', Icons.copy_outlined),
    (LyricsTextAction.copySong, 'Teljes dal másolása', Icons.copy_all_outlined),
  ];

  final isDesktop = _desktopPlatforms.contains(defaultTargetPlatform);
  LyricsTextAction? selected;

  if (position != null && isDesktop && context.mounted) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    selected = await showMenu<LyricsTextAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final (action, label, icon) in entries)
          PopupMenuItem(
            value: action,
            child: ListTile(
              leading: Icon(icon),
              title: Text(label),
              contentPadding: EdgeInsets.zero,
              mouseCursor: SystemMouseCursors.click,
            ),
          ),
      ],
    );
  } else if (context.mounted) {
    selected = await showModalBottomSheet<LyricsTextAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (action, label, icon) in entries)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.of(context).pop(action),
              ),
          ],
        ),
      ),
    );
  }

  if (selected == null || !context.mounted) return;
  await executeLyricsTextAction(
    context,
    selected,
    song: song,
    verse: verse,
    verseIndex: verseIndex,
  );
}

/// Runs a lyrics text action chosen from [showLyricsTextActionsMenu].
Future<void> executeLyricsTextAction(
  BuildContext context,
  LyricsTextAction action, {
  required Song song,
  ParsedVerse? verse,
  int? verseIndex,
}) async {
  switch (action) {
    case LyricsTextAction.selectText:
      await showLyricsSelectionDialog(
        context,
        song: song,
        initialVerseIndex: verseIndex,
      );
    case LyricsTextAction.copyVerse:
      if (verse != null) {
        await messengerService.copyToClipboard(friendlyVerseText(verse));
      }
    case LyricsTextAction.copySong:
      await messengerService.copyToClipboard(friendlySongLyricsOf(song).text);
  }
}
