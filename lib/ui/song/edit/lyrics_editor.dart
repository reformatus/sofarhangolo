import 'package:flutter/material.dart';

import '../../common/error/card.dart';
import '../../common/error/dialog.dart';
import '../../common/monospace.dart';

/// Full-bleed, monospace lyrics editor for the OpenSong format.
///
/// The text never word-wraps: [EditableText] with
/// [EditableText.forceLine] disabled sizes itself to its longest line
/// (never narrower than the viewport, thanks to the [ConstrainedBox]),
/// and the surrounding horizontal [SingleChildScrollView] scrolls what
/// does not fit. A floating info button at the top right opens a help
/// dialog about the format.
///
/// This is the raw [EditableText] rather than a [TextField] on purpose:
/// a [TextField] always adopts the width it is given ([forceLine] is not
/// exposed there), which would wrap lines at the viewport edge.
class OpenSongLyricsEditor extends StatefulWidget {
  const OpenSongLyricsEditor({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<OpenSongLyricsEditor> createState() => _OpenSongLyricsEditorState();
}

class _OpenSongLyricsEditorState extends State<OpenSongLyricsEditor> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: colors.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      minHeight: constraints.maxHeight,
                    ),
                    child: EditableText(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      scrollController: _scrollController,
                      maxLines: null,
                      expands: true,
                      forceLine: false,
                      keyboardType: TextInputType.multiline,
                      autocorrect: false,
                      enableSuggestions: false,
                      showCursor: true,
                      mouseCursor: SystemMouseCursors.text,
                      style: monospaceTextStyle.copyWith(
                        fontSize: 13,
                        height: 1.4,
                        color: colors.onSurface,
                      ),
                      cursorColor: colors.primary,
                      backgroundCursorColor: colors.outline,
                      selectionColor: colors.primary.withValues(alpha: 0.3),
                      selectionControls: materialTextSelectionControls,
                      contextMenuBuilder:
                          (context, editableTextState) =>
                              AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: editableTextState.contextMenuAnchors,
                                buttonItems:
                                    editableTextState.contextMenuButtonItems,
                              ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 12,
          child: IconButton.filledTonal(
            tooltip: 'Súgó',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showOpenSongHelpDialog(context),
          ),
        ),
      ],
    );
  }
}

/// Opens the OpenSong format help using the project's shared dialog.
Future<void> showOpenSongHelpDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => const ErrorDialog(
      type: LErrorType.info,
      title: 'OpenSong formátum',
      message:
          'A dalszöveg szakaszokból áll. Minden szakasz egy szögletes '
          'zárójeles címkével kezdődik egy saját sorban, például [Verze] '
          'vagy [Refrén].\n\n'
          'A ponttal (.) kezdődő sorok akkordsorok: a bennük lévő akkordok '
          'a következő szöveges sorhoz tartoznak, és szóközökkel igazodnak '
          'a hangzatokhoz.',
      icon: Icons.help_outline,
      showReportButton: false,
    ),
  );
}
