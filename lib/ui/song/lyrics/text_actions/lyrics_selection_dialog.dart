import 'package:flutter/material.dart';

import '../../../../config/config.dart';
import '../../../../data/song/song.dart';
import '../../../../services/text_export/song_lyrics.dart';
import '../../../../services/ui/messenger_service.dart';

/// Dialog for freely selecting and copying a song's lyrics in the
/// user-friendly format (pretty verse headers, no chords).
///
/// Uses a read-only text field instead of a [SelectionArea] because it needs
/// programmatic preselection of a verse, which the selection region API does
/// not expose. The field still provides native selection handles, the copy
/// toolbar and mouse drag-selection.
Future<void> showLyricsSelectionDialog(
  BuildContext context, {
  required Song song,
  int? initialVerseIndex,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        LyricsSelectionDialog(song: song, initialVerseIndex: initialVerseIndex),
  );
}

class LyricsSelectionDialog extends StatefulWidget {
  const LyricsSelectionDialog({
    required this.song,
    this.initialVerseIndex,
    super.key,
  });

  final Song song;

  /// Index of the verse to preselect, or `null` to leave the text unselected.
  final int? initialVerseIndex;

  @override
  State<LyricsSelectionDialog> createState() => _LyricsSelectionDialogState();
}

class _LyricsSelectionDialogState extends State<LyricsSelectionDialog> {
  late final FriendlyLyrics _lyrics;
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  /// Content width of the text field, captured from layout; used to compute
  /// the scroll target for revealing the preselection.
  double? _textWidth;
  bool _hasSelection = false;

  @override
  void initState() {
    super.initState();
    _lyrics = friendlySongLyricsOf(widget.song);
    _controller = TextEditingController(text: _lyrics.text);
    _controller.addListener(_updateSelectionState);
    _applyPreselection();
  }

  void _applyPreselection() {
    final block = widget.initialVerseIndex == null
        ? null
        : _lyrics.blocks
              .where((b) => b.verseIndex == widget.initialVerseIndex)
              .firstOrNull;
    if (block == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.selection = TextSelection(
        baseOffset: block.start,
        extentOffset: block.end,
      );
      // Focus so the selection renders visibly (with handles on touch
      // platforms), then scroll the verse into view.
      _focusNode.requestFocus();
      _revealOffset(block.start);
    });
  }

  /// Scrolls the field so the given character offset becomes visible. The
  /// target is computed from a TextPainter laid out with the same style and
  /// width as the field.
  void _revealOffset(int characterOffset) {
    final width = _textWidth;
    if (width == null || width <= 0 || !_scrollController.hasClients) return;

    final textPainter = TextPainter(
      text: TextSpan(
        text: _controller.text,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);

    final caretTop = textPainter
        .getOffsetForCaret(TextPosition(offset: characterOffset), Rect.zero)
        .dy;
    final maxExtent = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo((caretTop - 24).clamp(0.0, maxExtent));
  }

  void _updateSelectionState() {
    final selection = _controller.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;
    if (hasSelection != _hasSelection) {
      setState(() => _hasSelection = hasSelection);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _copySelection() {
    final text = _controller.selection.textInside(_controller.text);
    if (text.isNotEmpty) messengerService.copyToClipboard(text);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: appConfig.breakpoints.tabletFromWidth,
        ),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Szövegkijelölés'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
            actionsPadding: EdgeInsets.only(right: 8),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Matches the TextField's horizontal contentPadding below.
              _textWidth = constraints.maxWidth - 32;
              return SingleChildScrollView(
                controller: _scrollController,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  readOnly: true,
                  maxLines: null,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              );
            },
          ),
          persistentFooterButtons: [
            TextButton.icon(
              onPressed: () => messengerService.copyToClipboard(_lyrics.text),
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Teljes dal'),
            ),
            FilledButton.icon(
              onPressed: _hasSelection ? _copySelection : null,
              icon: const Icon(Icons.copy),
              label: const Text('Másolás'),
            ),
          ],
        ),
      ),
    );
  }
}
