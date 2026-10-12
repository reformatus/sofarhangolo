import 'package:flutter/material.dart';

import '../../common/monospace.dart';
import '../../common/notice/card.dart';
import 'opensong_help_dialog.dart';
import 'opensong_input.dart';

export 'opensong_help_dialog.dart' show showOpenSongHelpDialog;

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
/// exposed there), which would wrap lines at the viewport edge. Because there
/// are no `inputFormatters` either, the OpenSong conveniences (auto leading
/// space, row-marker override, focus-loss normalisation) are applied through a
/// controller listener using the pure helpers in `opensong_input.dart`.
class OpenSongLyricsEditor extends StatefulWidget {
  const OpenSongLyricsEditor({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<OpenSongLyricsEditor> createState() => _OpenSongLyricsEditorState();
}

class _OpenSongLyricsEditorState extends State<OpenSongLyricsEditor> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  /// The last value we accepted. Compared against the controller to tell the
  /// user's edits apart from the values we write back ourselves, which is what
  /// keeps the listener from looping.
  late TextEditingValue _lastValue = widget.controller.value;

  /// Offset of the leading space we auto-inserted and whose very next typed
  /// character may still replace it (see [replaceMarkerAfterAutoSpace]).
  int? _autoSpaceOffset;

  bool _showFormatWarning = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _showFormatWarning = hasOpenSongFormattingWarning(widget.controller.text);
    widget.controller.addListener(_onControllerChanged);
    widget.controller.addListener(_refreshFormatWarning);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    // Leaving the editor is when the missing leading spaces are added; running
    // it here too covers navigation that disposes us without a separate
    // focus-loss event, so the parent's pending autosave flushes the fixed
    // text.
    _normalizeLeadingSpaces();
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.removeListener(_refreshFormatWarning);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _normalizeLeadingSpaces();
  }

  /// Reacts to every controller change: it applies the one-time row-marker
  /// override, then auto-inserts a leading space on a fresh empty line.
  void _onControllerChanged() {
    final value = widget.controller.value;
    if (value == _lastValue) return;
    final previous = _lastValue;
    _lastValue = value;

    // 1) The row-marker override consumes the auto-inserted space at most once.
    final spaceOffset = _autoSpaceOffset;
    _autoSpaceOffset = null;
    if (spaceOffset != null) {
      final replaced = replaceMarkerAfterAutoSpace(
        previous,
        value,
        spaceOffset,
      );
      if (replaced != null) {
        _applyValue(replaced);
        return;
      }
    }

    // 2) A new empty line gets its mandatory leading space.
    final spaced = autoLeadingSpace(previous, value);
    if (spaced != null) {
      _applyValue(spaced.value);
      _autoSpaceOffset = spaced.offset;
    }
  }

  /// Writes [value] back to the controller, recording it first so the listener
  /// call it triggers is recognised as our own edit and left alone.
  void _applyValue(TextEditingValue value) {
    _lastValue = value;
    widget.controller.value = value;
  }

  void _refreshFormatWarning() {
    if (_disposed) return;
    final warning = hasOpenSongFormattingWarning(widget.controller.text);
    if (warning != _showFormatWarning) {
      setState(() => _showFormatWarning = warning);
    }
  }

  /// Adds the mandatory leading space to lyric lines that lack one, keeping the
  /// caret roughly where it was.
  void _normalizeLeadingSpaces() {
    final controller = widget.controller;
    final text = controller.text;
    final normalized = ensureLyricLeadingSpaces(text);
    if (normalized == text) return;

    final caret = controller.selection.baseOffset;
    _applyValue(
      TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(
          offset: caret.isNegative
              ? normalized.length
              : caret.clamp(0, normalized.length),
        ),
      ),
    );
    // The normalised text must not arm the marker override.
    _autoSpaceOffset = null;
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
                      contextMenuBuilder: (context, editableTextState) =>
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
        // A floating, non-blocking warning so the editor never gets pushed
        // around when the format is invalid.
        if (_showFormatWarning)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: IgnorePointer(
                  child: LNoticeCard(
                    type: LNoticeType.warning,
                    icon: Icons.warning_amber_rounded,
                    title: 'Hibás OpenSong formátum',
                    message:
                        'Akkordsor mellett olyan szövegsor szerepel, amely '
                        'nem szóközzel kezdődik. A szövegsoroknak vezető '
                        'szóközzel kell kezdődniük.',
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
