import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/song/song.dart';
import '../../../data/song/song_fields.dart';

/// Invisible marker embedded at selectable text boundaries (see
/// [SelectableDetailsList]); converted to a real line break on copy.
/// U+200B (zero-width space) renders nothing and does not affect layout.
const selectionBreakMarker = '\u200B';

// Helper functions for song details
//
// Details are rendered plain here; the details bottom sheet wraps the whole
// list in a single SelectionArea so selections can span items.
List<Widget> getDetailsSummaryContent(
  Song song,
  BuildContext context, [
  Map<String, SongField>? registry,
]) {
  // Summary chips come from the effective registry: defaults in
  // vocabulary order, then bank-defined fields. Core fields are immune
  // to overlays; icons fall back the same way as in the details list.
  final effectiveRegistry = registry ?? defaultSongFieldRegistry;
  List<Widget> detailsSummary = [];
  for (final field in effectiveRegistry.values) {
    if (!field.hasUse(SongFieldUse.summary)) continue;
    final display = song.contentDisplay(field.apiName);
    if (display != null) {
      detailsSummary.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              field.icon ?? Icons.help_outline,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 3),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                display,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                softWrap: true,
              ),
            ),
          ],
        ),
      );
    }
  }
  return detailsSummary;
}

List<Widget> getDetailsContent(
  Song song,
  BuildContext context, [
  Map<String, SongField>? registry,
]) {
  final effectiveRegistry = registry ?? defaultSongFieldRegistry;
  List<Widget> detailsContent = [];
  for (final field in effectiveRegistry.values) {
    // Only fields with a definition and a details use show up; everything
    // else is known-but-unused vocabulary or bank-custom data.
    if (!field.hasUse(SongFieldUse.details)) continue;
    final display = song.contentDisplay(field.apiName);
    if (display != null) {
      detailsContent.add(
        ListTile(
          visualDensity: VisualDensity.compact,
          leading: Icon(field.icon ?? Icons.help_outline),
          title: Text(
            field.title,
            style: Theme.of(context).primaryTextTheme.labelMedium,
          ),
          // Leading marker: line break between the item title and its value
          // on copy. Trailing marker: line break between items on copy.
          subtitle: Text('$selectionBreakMarker$display$selectionBreakMarker'),
          subtitleTextStyle: Theme.of(context).listTileTheme.titleTextStyle,
        ),
      );
    }
  }
  return detailsContent;
}

/// A [SelectionArea] over [children] whose copies keep one item per line.
///
/// Flutter's selection system concatenates the raw text of selected widgets
/// with no separators (and drag selections never include separate separator
/// widgets), so each item embeds invisible [selectionBreakMarker] characters
/// at its boundaries. This wrapper tracks the selected text and overrides the
/// copy action to turn the markers into real line breaks.
class SelectableDetailsList extends StatefulWidget {
  const SelectableDetailsList({required this.children, super.key});

  final List<Widget> children;

  @override
  State<SelectableDetailsList> createState() => _SelectableDetailsListState();
}

class _SelectableDetailsListState extends State<SelectableDetailsList> {
  String? _selectedText;

  Future<void> _copySelection() async {
    final text = _selectedText;
    if (text == null) return;
    await Clipboard.setData(
      ClipboardData(text: text.replaceAll(selectionBreakMarker, '\n')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The override must be an ANCESTOR of SelectionArea: copy shortcuts
    // (Ctrl/Cmd+C) resolve from the region's focus node upwards, and
    // SelectableRegion registers its own copy action as overridable — an
    // Actions entry above it wins. The context menu copy button is covered
    // by the custom contextMenuBuilder below.
    return Actions(
      actions: {
        CopySelectionTextIntent: _CopySelectionWithBreaksAction(
          () => _selectedText,
        ),
      },
      child: SelectionArea(
        onSelectionChanged: (content) => _selectedText = content?.plainText,
        contextMenuBuilder: (context, selectableRegionState) {
          final items = selectableRegionState.contextMenuButtonItems
              .map(
                (item) => item.type == ContextMenuButtonType.copy
                    ? ContextMenuButtonItem(
                        type: ContextMenuButtonType.copy,
                        onPressed: _copySelection,
                      )
                    : item,
              )
              .toList();
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: selectableRegionState.contextMenuAnchors,
            buttonItems: items,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widget.children,
        ),
      ),
    );
  }
}

class _CopySelectionWithBreaksAction extends Action<CopySelectionTextIntent> {
  _CopySelectionWithBreaksAction(this.selectedText);

  final String? Function() selectedText;

  @override
  Object? invoke(CopySelectionTextIntent intent, [BuildContext? context]) {
    final text = selectedText();
    if (text == null) return null;
    Clipboard.setData(
      ClipboardData(text: text.replaceAll(selectionBreakMarker, '\n')),
    );
    return null;
  }
}
