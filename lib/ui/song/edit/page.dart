import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/config.dart';
import '../../../data/song/extensions.dart';
import '../../../data/song/song.dart';
import '../../../services/assets/pick_asset.dart';
import '../../../services/preferences/providers/lyrics_view_style.dart';
import '../../common/adaptive_page/page.dart';
import '../../common/confirm_dialog.dart';
import '../../common/error/card.dart';
import '../state.dart';
import '../view_chooser.dart';
import 'attachment_editor.dart';
import 'autosave_indicator.dart';
import 'details_pane.dart';
import 'editor_controller.dart';
import 'editor_view_toggle.dart';
import 'lyrics_editor.dart';
import 'lyrics_preview.dart';

/// Smallest editor width we accept next to the preview column; below it the
/// lyrics area switches to the tabbed layout.
const double _minEditorWidth = 480;

/// Loads the local song [songUuid] and shows the editor for it.
class LocalSongEditPage extends ConsumerWidget {
  const LocalSongEditPage(this.songUuid, {super.key});

  final String songUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(localSongEditorControllerProvider(songUuid))) {
      AsyncError(:final error, :final stackTrace) => Center(
        child: LErrorCard.fromError(
          error: error,
          stackTrace: stackTrace,
          title: 'Nem sikerült betölteni a dalt.',
          icon: Icons.music_note,
        ),
      ),
      AsyncData() => LocalSongEditor(songUuid: songUuid),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// The local song editor UI. The draft, autosave and deletion live in
/// [LocalSongEditorController]; this only wires text fields, tabs and focus
/// to it. The controller must already be loaded (see [LocalSongEditPage]).
class LocalSongEditor extends ConsumerStatefulWidget {
  const LocalSongEditor({super.key, required this.songUuid});

  final String songUuid;

  @override
  ConsumerState<LocalSongEditor> createState() => _LocalSongEditorState();
}

class _LocalSongEditorState extends ConsumerState<LocalSongEditor>
    with SingleTickerProviderStateMixin {
  /// The action bar is narrower than the window (shell chrome chomps off the
  /// sides), and the segmented view chooser is ~500px wide, so collapse it to
  /// the dropdown below this page width.
  static const double _viewChooserDropdownBelow = 620;

  late final _provider = localSongEditorControllerProvider(widget.songUuid);

  /// Cached: child widgets may edit the text while this widget is being
  /// unmounted, when `ref.read` is no longer allowed.
  late final LocalSongEditorController _controller = ref.read(
    _provider.notifier,
  );
  LocalSongEditorState get _state => ref.read(_provider).requireValue;

  late final TextEditingController _titleController = TextEditingController(
    text: _state.title,
  );
  late final TextEditingController _lyricsController = TextEditingController(
    text: _state.lyrics,
  );
  late final FocusNode _titleFocus = FocusNode();
  late final TabController _tabsController = TabController(
    length: 2,
    vsync: this,
  );

  /// Whether the lyrics area is currently in the tabbed (too-narrow) layout.
  /// Decided from the body constraints and mirrored into the action bar so
  /// the edit/preview switch lives with the other contextual actions.
  bool _lyricsTabbed = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_titleChanged);
    _lyricsController.addListener(_lyricsChanged);
  }

  @override
  void dispose() {
    // Write a pending edit now (the fields have settled: children are already
    // disposed), so a quick back navigation does not lose it.
    _controller.flush();
    _titleController.removeListener(_titleChanged);
    _lyricsController.removeListener(_lyricsChanged);
    _titleController.dispose();
    _lyricsController.dispose();
    _titleFocus.dispose();
    _tabsController.dispose();
    super.dispose();
  }

  void _titleChanged() => _controller.setTitle(_titleController.text);
  void _lyricsChanged() => _controller.setLyrics(_lyricsController.text);

  Future<void> _deleteSong() async {
    var confirmed = false;
    await showDialog(
      context: context,
      builder: (context) => ConfirmDialog(
        title: 'Dal törlése',
        actionLabel: 'Törlés',
        actionIcon: Icons.delete_outline,
        dangerousAction: true,
        actionOnPressed: () async {
          try {
            await _controller.delete();
            confirmed = true;
          } catch (_) {
            // Already logged; the controller shows the error status. Let the
            // dialog close instead of hanging on the failed action.
          }
        },
      ),
    );
    if (!mounted || !confirmed) return;
    // The deleted song's page may sit directly below us in the stack and
    // would only show a "not found" card, so return to the songs list.
    context.go('/bank');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider).requireValue;
    final song = state.song;
    final viewType =
        ref.watch(viewTypeForProvider(song, null)).value ?? SongViewType.chords;
    final previewWidth = ref
        .watch(lyricsViewStylePreferencesProvider)
        .verseCardColumnWidth
        .toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile: reuse the app's tablet breakpoint.
        final isMobile =
            constraints.maxWidth <= appConfig.breakpoints.tabletFromWidth;
        final isLyricsView =
            viewType == SongViewType.lyrics || viewType == SongViewType.chords;

        return AdaptivePage(
          title: 'Dal szerkesztése',
          titleWidget: Align(
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: _titleController,
              focusNode: _titleFocus,
              style: Theme.of(context).appBarTheme.titleTextStyle,
              // No collapsed decoration: the underline stays visible.
              decoration: const InputDecoration(
                hintText: 'Dal címe',
                isDense: true,
              ),
            ),
          ),
          body: _buildBody(state, viewType, previewWidth),
          rightDrawer: DetailsPane(
            song: song,
            contentMap: state.contentMap,
            keyField: state.keyField,
            onFieldChanged: _controller.setMetadataField,
            onKeysChanged: _controller.setKeys,
          ),
          rightDrawerIcon: Icons.info_outline,
          rightDrawerTooltip: 'Részletek',
          actionBarChildren: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ViewChooser(
                song: song,
                songSlide: null,
                useDropdown: constraints.maxWidth < _viewChooserDropdownBelow,
                // The editor can attach sheets, so let the SVG/PDF views be
                // selected even before anything is attached.
                allowUnavailableViews: true,
              ),
            ),
            // When the editor and preview are tabbed, their switch lives
            // here with the other contextual actions.
            if (isLyricsView && _lyricsTabbed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ListenableBuilder(
                  listenable: _tabsController,
                  builder: (context, _) => EditorViewToggle(
                    selectedIndex: _tabsController.index,
                    compact: isMobile,
                    onChanged: _tabsController.animateTo,
                  ),
                ),
              ),
            ..._contextualActions(state.song, viewType),
          ],
          appBarActions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AutosaveIndicator(
                status: state.status,
                onRetry: _controller.retrySave,
              ),
            ),
            IconButton(
              tooltip: 'Dal törlése',
              color: Theme.of(context).colorScheme.error,
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteSong,
            ),
          ],
        );
      },
    );
  }

  /// Actions belonging to the currently selected, *attached* sheet view. When
  /// nothing is attached the attach button lives in the centered empty state
  /// instead, so the action bar stays empty.
  List<Widget> _contextualActions(Song song, SongViewType viewType) {
    final field = switch (viewType) {
      SongViewType.svg => 'svg',
      SongViewType.pdf => 'pdf',
      SongViewType.lyrics || SongViewType.chords => null,
    };
    if (field == null) return const [];

    final attached = field == 'svg' ? song.hasSvg : song.hasPdf;
    if (!attached) return const [];

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: FilledButton.tonalIcon(
          onPressed: () => _replaceAttachment(field),
          icon: const Icon(Icons.sync),
          label: const Text('Csere'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => _removeAttachment(field),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eltávolítás'),
        ),
      ),
    ];
  }

  /// Picks a file for [field] and stores it as the song's attachment
  /// (replacing any existing one).
  Future<void> _replaceAttachment(String field) async {
    final bytes = await pickAssetBytes(field);
    if (bytes == null || !mounted) return;
    await _controller.attach(field, bytes);
  }

  Future<void> _removeAttachment(String field) =>
      _controller.removeAttachment(field);

  Widget _buildBody(
    LocalSongEditorState state,
    SongViewType viewType,
    double previewWidth,
  ) {
    return switch (viewType) {
      SongViewType.svg => AttachmentEditor(
        song: state.song,
        isSvg: true,
        onAttach: () => _replaceAttachment('svg'),
      ),
      SongViewType.pdf => AttachmentEditor(
        song: state.song,
        isSvg: false,
        onAttach: () => _replaceAttachment('pdf'),
      ),
      SongViewType.lyrics ||
      SongViewType.chords => _buildLyricsArea(state.song, previewWidth),
    };
  }

  Widget _buildLyricsArea(Song song, double previewWidth) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final editor = OpenSongLyricsEditor(controller: _lyricsController);
        final preview = LyricsPreview(song: song, text: _lyricsController);

        // Side-by-side columns while the editor keeps enough room; below
        // that, fall back to a tabbed layout whose switch lives in the
        // action bar.
        final tabbed = constraints.maxWidth - previewWidth < _minEditorWidth;
        _syncLyricsTabbed(tabbed);

        if (!tabbed) {
          return Row(
            children: [
              Expanded(child: editor),
              SizedBox(width: previewWidth, child: preview),
            ],
          );
        }

        // Swipeable; the switch is in the action bar.
        return TabBarView(
          controller: _tabsController,
          children: [editor, preview],
        );
      },
    );
  }

  /// Keeps the action bar's edit/preview switch in sync with the tabbed
  /// lyrics layout, which is decided from the body constraints (the shell and
  /// drawers make those differ from the page width).
  void _syncLyricsTabbed(bool tabbed) {
    if (tabbed == _lyricsTabbed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && tabbed != _lyricsTabbed) {
        setState(() => _lyricsTabbed = tabbed);
      }
    });
  }
}
