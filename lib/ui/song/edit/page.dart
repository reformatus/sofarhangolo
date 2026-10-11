import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/config.dart';
import '../../../data/log/logger.dart';
import '../../../data/song/extensions.dart';
import '../../../data/song/song.dart';
import '../../../services/assets/get_song_asset.dart';
import '../../../services/assets/pick_asset.dart';
import '../../../services/assets/write_song_asset.dart';
import '../../../services/preferences/providers/lyrics_view_style.dart';
import '../../../services/song/from_uuid.dart';
import '../../../services/songs/write_song.dart';
import '../../common/adaptive_page/page.dart';
import '../../common/confirm_dialog.dart';
import '../../common/error/card.dart';
import '../state.dart';
import '../view_chooser.dart';
import 'attachment_editor.dart';
import 'autosave_indicator.dart';
import 'details_pane.dart';
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
    return switch (ref.watch(songFromUuidProvider(songUuid))) {
      AsyncError(:final error, :final stackTrace) => Center(
        child: LErrorCard.fromError(
          error: error,
          stackTrace: stackTrace,
          title: 'Nem sikerült betölteni a dalt.',
          icon: Icons.music_note,
        ),
      ),
      AsyncData(:final value) => LocalSongEditor(song: value),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// The local song editor. Saving is automatic: content changes are debounced
/// and written with [writeLocalSong], with the result reflected in the app
/// bar's autosave indicator.
class LocalSongEditor extends ConsumerStatefulWidget {
  const LocalSongEditor({super.key, required this.song});

  final Song song;

  @override
  ConsumerState<LocalSongEditor> createState() => _LocalSongEditorState();
}

class _LocalSongEditorState extends ConsumerState<LocalSongEditor>
    with SingleTickerProviderStateMixin {
  static const _saveDebounce = Duration(milliseconds: 500);
  static const _savedLinger = Duration(seconds: 2);

  /// The action bar is narrower than the window (shell chrome chomps off the
  /// sides), and the segmented view chooser is ~500px wide, so collapse it to
  /// the dropdown below this page width.
  static const double _viewChooserDropdownBelow = 620;

  late Song _song = widget.song;
  late final Map<String, Object> _contentMap = Map.of(widget.song.contentMap);
  late List<KeyField> _keyField = List.of(widget.song.keyField);
  late final TextEditingController _titleController = TextEditingController(
    text: _song.title,
  );
  late final TextEditingController _lyricsController = TextEditingController(
    text: _song.lyrics ?? '',
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

  AutosaveStatus _autosaveStatus = AutosaveStatus.idle;
  Timer? _autosaveTimer;
  bool _dirty = false;
  bool _saving = false;
  bool _deleteConfirmed = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_markChanged);
    _lyricsController.addListener(_markChanged);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    // Flush any pending edit so a quick back navigation does not lose it.
    if (_dirty) {
      unawaited(writeLocalSong(_draft()));
    }
    _titleController.removeListener(_markChanged);
    _lyricsController.removeListener(_markChanged);
    _titleController.dispose();
    _lyricsController.dispose();
    _titleFocus.dispose();
    _tabsController.dispose();
    super.dispose();
  }

  Song _draft() => _song.copyWith(
    title: _titleController.text,
    lyrics: _lyricsController.text,
    contentMap: Map.of(_contentMap),
    keyField: List.of(_keyField),
  );

  void _markChanged() {
    _dirty = true;
    _autosaveTimer?.cancel();
    setState(() => _autosaveStatus = AutosaveStatus.saving);
    _autosaveTimer = Timer(_saveDebounce, _save);
  }

  /// Updates one metadata field; blank values clear the key entirely.
  void _setMetadataField(String apiName, Object? value) {
    final cleared =
        value == null ||
        (value is String && value.trim().isEmpty) ||
        (value is List && value.isEmpty);
    setState(() {
      if (cleared) {
        _contentMap.remove(apiName);
      } else {
        _contentMap[apiName] = value;
      }
    });
    _markChanged();
  }

  void _setKeys(List<KeyField> keys) {
    setState(() => _keyField = List.of(keys));
    _markChanged();
  }

  Future<void> _save() async {
    if (_saving) {
      // A write is already in flight; try again once it finishes.
      _autosaveTimer = Timer(_saveDebounce, _save);
      return;
    }

    _saving = true;
    try {
      final saved = await writeLocalSong(_draft());
      if (!mounted) return;
      _song = saved;
      _dirty = false;
      _showSaved();
    } catch (error, stackTrace) {
      if (!mounted) return;
      log.warning('Nem sikerült elmenteni a helyi dalt.', error, stackTrace);
      setState(() => _autosaveStatus = AutosaveStatus.error);
    } finally {
      _saving = false;
    }
  }

  /// Shows the transient "saved" confirmation, then settles to the check.
  void _showSaved() {
    setState(() => _autosaveStatus = AutosaveStatus.saved);
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_savedLinger, () {
      if (!mounted) return;
      setState(() => _autosaveStatus = AutosaveStatus.upToDate);
    });
  }

  Future<void> _deleteSong() async {
    _deleteConfirmed = false;
    await showDialog(
      context: context,
      builder: (context) => ConfirmDialog(
        title: 'Dal törlése',
        actionLabel: 'Törlés',
        actionIcon: Icons.delete_outline,
        dangerousAction: true,
        actionOnPressed: () async {
          _autosaveTimer?.cancel();
          _dirty = false;
          _deleteConfirmed = true;
          await deleteLocalSong(_song);
        },
      ),
    );
    if (!mounted || !_deleteConfirmed) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewType =
        ref.watch(viewTypeForProvider(_song, null)).value ??
        SongViewType.chords;
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
            viewType == SongViewType.lyrics ||
            viewType == SongViewType.chords;

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
          body: _buildBody(viewType, previewWidth),
          rightDrawer: DetailsPane(
            song: _song,
            contentMap: _contentMap,
            keyField: _keyField,
            onFieldChanged: _setMetadataField,
            onKeysChanged: _setKeys,
          ),
          rightDrawerIcon: Icons.info_outline,
          rightDrawerTooltip: 'Részletek',
          actionBarChildren: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ViewChooser(
                song: _song,
                songSlide: null,
                useDropdown:
                    constraints.maxWidth < _viewChooserDropdownBelow,
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
            ..._contextualActions(viewType),
          ],
          appBarActions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AutosaveIndicator(
                status: _autosaveStatus,
                onRetry: _save,
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
  List<Widget> _contextualActions(SongViewType viewType) {
    final field = switch (viewType) {
      SongViewType.svg => 'svg',
      SongViewType.pdf => 'pdf',
      SongViewType.lyrics || SongViewType.chords => null,
    };
    if (field == null) return const [];

    final attached = field == 'svg' ? _song.hasSvg : _song.hasPdf;
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
    if (bytes == null) return;

    try {
      await writeLocalSongAsset(_song, field, bytes);
      if (!mounted) return;
      ref.invalidate(getSongAssetProvider(_song, field));
      _showSaved();
    } catch (error, stackTrace) {
      if (!mounted) return;
      log.warning('Nem sikerült csatolni a kottát.', error, stackTrace);
      setState(() => _autosaveStatus = AutosaveStatus.error);
    }
  }

  Future<void> _removeAttachment(String field) async {
    try {
      await removeLocalSongAsset(_song, field);
      if (!mounted) return;
      ref.invalidate(getSongAssetProvider(_song, field));
      _showSaved();
    } catch (error, stackTrace) {
      if (!mounted) return;
      log.warning('Nem sikerült eltávolítani a kottát.', error, stackTrace);
      setState(() => _autosaveStatus = AutosaveStatus.error);
    }
  }

  Widget _buildBody(SongViewType viewType, double previewWidth) {
    return switch (viewType) {
      SongViewType.svg => AttachmentEditor(
        song: _song,
        isSvg: true,
        onAttach: () => _replaceAttachment('svg'),
      ),
      SongViewType.pdf => AttachmentEditor(
        song: _song,
        isSvg: false,
        onAttach: () => _replaceAttachment('pdf'),
      ),
      SongViewType.lyrics || SongViewType.chords => _buildLyricsArea(
        previewWidth,
      ),
    };
  }

  Widget _buildLyricsArea(double previewWidth) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final editor = OpenSongLyricsEditor(controller: _lyricsController);
        final preview = LyricsPreview(song: _song, text: _lyricsController);

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
