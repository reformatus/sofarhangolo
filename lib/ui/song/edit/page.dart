import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/config.dart';
import '../../../data/song/extensions.dart';
import '../../../data/song/lyrics/format.dart';
import '../../../data/song/lyrics/parser.dart';
import '../../../data/song/song.dart';
import '../../../data/song/transpose.dart';
import '../../../services/preferences/providers/lyrics_view_style.dart';
import '../../common/adaptive_page/page.dart';
import '../lyrics/view.dart';
import '../state.dart';
import '../view_chooser.dart';
import 'autosave_indicator.dart';
import 'lyrics_editor.dart';

/// Smallest editor width we accept next to the preview column; below it the
/// lyrics area switches to the tabbed layout.
const double _minEditorWidth = 480;

/// Mock of the local song editor (Phase B wireframe).
///
/// All data is hardcoded and nothing is persisted — this exists to shape
/// the UX before any logic is wired up. The layout mirrors the song page:
/// the view switcher lives in the bottom action bar, the lyrics editor and
/// a lyrics preview fill the main area side by side (flush, no cards), and
/// the song details live in the right pane.
class LocalSongEditPage extends ConsumerStatefulWidget {
  const LocalSongEditPage({super.key});

  @override
  ConsumerState<LocalSongEditPage> createState() => _LocalSongEditPageState();
}

class _LocalSongEditPageState extends ConsumerState<LocalSongEditPage>
    with SingleTickerProviderStateMixin {
  static final Song _mockSong = Song(
    uuid: 'mock-local-song',
    title: 'Áldjad, én lelkem, az Urat',
    lyrics: _mockLyrics,
    lyricsFormat: LyricsFormat.opensong,
    keyField: [KeyField('C', 'major')],
    contentMap: {
      'svg': 'local://mock-svg-reference',
      'pdf': 'local://mock-pdf-reference',
    },
  );

  static const _mockLyrics = '''
[Verze]
.        G               D
Megáldott az Úr a házamtelekén,
.      Em            C           G
ki félte őtet szívvel és lélekkel.
.          G                D
Áldás és kegyelem árad szívére,
.     Em      C               G     D
és a keze munkáját gyümölccsel koronázza.

[Refrén]
.    C            G
Áldjad, én lelkem, az Urat,
.      Em               C        G
és mind bensőm az ő szent nevét!
.   C            G
Áldjad, én lelkem, az Urat,
.      Em         D        C   G
és ne feledkezzél meg jótéteményéről!
''';

  late final TextEditingController _titleController = TextEditingController(
    text: _mockSong.title,
  );
  late final TextEditingController _lyricsController = TextEditingController(
    text: _mockLyrics,
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

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onContentChanged);
    _lyricsController.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _titleController.removeListener(_onContentChanged);
    _lyricsController.removeListener(_onContentChanged);
    _titleController.dispose();
    _lyricsController.dispose();
    _titleFocus.dispose();
    _tabsController.dispose();
    super.dispose();
  }

  /// Mock autosave: any change shows the saving state, then the confirmation
  /// (check + "Mentve"), then settles to just the check. An empty title
  /// stands in for a save failure so the error state is reachable for design
  /// review.
  void _onContentChanged() {
    _autosaveTimer?.cancel();
    setState(() => _autosaveStatus = AutosaveStatus.saving);
    _autosaveTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      if (_titleController.text.trim().isEmpty) {
        setState(() => _autosaveStatus = AutosaveStatus.error);
        return;
      }
      setState(() => _autosaveStatus = AutosaveStatus.saved);
      _autosaveTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _autosaveStatus = AutosaveStatus.upToDate);
      });
    });
  }

  /// The action bar is narrower than the window (shell chrome chomps off the
  /// sides), and the segmented view chooser is ~500px wide, so collapse it to
  /// the dropdown below this page width.
  static const double _viewChooserDropdownBelow = 620;

  @override
  Widget build(BuildContext context) {
    final viewType =
        ref.watch(viewTypeForProvider(_mockSong, null)).value ??
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
          rightDrawer: const _DetailsPane(),
          rightDrawerIcon: Icons.info_outline,
          rightDrawerTooltip: 'Részletek',
          actionBarChildren: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ViewChooser(
                song: _mockSong,
                songSlide: null,
                useDropdown:
                    constraints.maxWidth < _viewChooserDropdownBelow,
              ),
            ),
            // When the editor and preview are tabbed, their switch lives
            // here with the other contextual actions.
            if (isLyricsView && _lyricsTabbed) _editorViewToggle(isMobile),
            ..._contextualActions(viewType),
          ],
          appBarActions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AutosaveIndicator(
                status: _autosaveStatus,
                onRetry: _onContentChanged,
              ),
            ),
            IconButton(
              tooltip: 'Dal törlése',
              color: Theme.of(context).colorScheme.error,
              icon: const Icon(Icons.delete_outline),
              onPressed: () {},
            ),
          ],
        );
      },
    );
  }

  /// Edit/preview switch for the tabbed lyrics layout: two buttons styled
  /// like the sheet attachment actions (filled tonal when active, outlined
  /// otherwise). On mobile the selected one drops its label.
  Widget _editorViewToggle(bool isMobile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListenableBuilder(
        listenable: _tabsController,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _editorViewButton(
              index: 0,
              icon: Icons.edit_outlined,
              label: 'Szerkesztés',
              isMobile: isMobile,
            ),
            const SizedBox(width: 8),
            _editorViewButton(
              index: 1,
              icon: Icons.visibility_outlined,
              label: 'Előnézet',
              isMobile: isMobile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorViewButton({
    required int index,
    required IconData icon,
    required String label,
    required bool isMobile,
  }) {
    final selected = _tabsController.index == index;
    void onPressed() => _tabsController.animateTo(index);
    final showLabel = !(isMobile && selected);
    final labelWidget = Text(
      label,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );

    if (selected) {
      return showLabel
          ? FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: labelWidget,
            )
          : FilledButton.tonal(onPressed: onPressed, child: Icon(icon));
    }
    return showLabel
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: labelWidget,
          )
        : OutlinedButton(onPressed: onPressed, child: Icon(icon));
  }

  /// Actions belonging to the currently selected view, mirroring the song
  /// page's action bar. The sheet views need an attachment instead of a view
  /// switch, so they get their own contextual buttons.
  List<Widget> _contextualActions(SongViewType viewType) {
    final attached = switch (viewType) {
      SongViewType.svg => _mockSong.hasSvg,
      SongViewType.pdf => _mockSong.hasPdf,
      SongViewType.lyrics || SongViewType.chords => null,
    };
    if (attached == null) return const [];

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: attached
            ? FilledButton.tonalIcon(
                onPressed: () {},
                icon: const Icon(Icons.sync),
                label: const Text('Csere'),
              )
            : FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.upload_file),
                label: const Text('Fájl csatolása'),
              ),
      ),
      if (attached)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {},
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eltávolítás'),
          ),
        ),
    ];
  }

  Widget _buildBody(SongViewType viewType, double previewWidth) {
    return switch (viewType) {
      SongViewType.svg => _AttachmentEditor(
        icon: Icons.image_outlined,
        attached: _mockSong.hasSvg,
      ),
      SongViewType.pdf => _AttachmentEditor(
        icon: Icons.picture_as_pdf_outlined,
        attached: _mockSong.hasPdf,
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
        final preview = _LyricsPreview(song: _mockSong, text: _lyricsController);

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

/// Full-bleed attachment surface (SVG/PDF), matching the song page's sheet
/// views: it fills the whole page area. The contextual replace/remove/attach
/// actions live in the page's action bar, not here.
class _AttachmentEditor extends StatelessWidget {
  const _AttachmentEditor({required this.icon, required this.attached});

  final IconData icon;
  final bool attached;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(icon, size: 64, color: colors.outline),
            Text(
              attached ? 'Csatolmány feltöltve' : 'Még nincs kotta csatolva',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live lyrics preview column: parses the editor's text as it changes and
/// lays the verses out like the song page does.
class _LyricsPreview extends StatelessWidget {
  const _LyricsPreview({required this.song, required this.text});

  final Song song;
  final TextEditingController text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colors.surfaceContainer,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: text,
        builder: (context, value, _) => LayoutBuilder(
          builder: (context, constraints) {
            final verses = LyricsParser.forFormat(
              song.lyricsFormat,
            ).parse(value.text);
            final verseWidth = min(constraints.maxWidth, 560.0);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: colors.outline,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Előnézet',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: colors.outline),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: Wrap(
                        direction: Axis.vertical,
                        children: [
                          ...verses.indexed.map(
                            (entry) => SizedBox(
                              width: verseWidth,
                              child: VerseCard(
                                song,
                                entry.$2 as OpenSongVerse,
                                transpose: SongTranspose(),
                                verseIndex: entry.$1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailsPane extends StatelessWidget {
  const _DetailsPane();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 20,
        children: [
          const _OriginalSongCard(),
          const _KeySection(),
        ],
      ),
    );
  }
}

class _OriginalSongCard extends StatelessWidget {
  const _OriginalSongCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: colors.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Eredeti dal',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.onTertiaryContainer,
                  ),
                ),
              ],
            ),
            Text(
              'Áldjad, én lelkem, az Urat — Sófár Kottatár',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onTertiaryContainer,
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.sync_problem_outlined,
                  size: 16,
                  color: colors.onTertiaryContainer,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Megváltozott a másolás óta.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: colors.onTertiaryContainer,
                ),
                onPressed: () {},
                child: const Text('Eredeti megtekintése'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeySection extends StatelessWidget {
  const _KeySection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text('Hangnem', style: Theme.of(context).textTheme.titleMedium),
        Wrap(
          spacing: 8,
          children: [
            InputChip(
              label: const Text('C-dúr'),
              onDeleted: () {},
              deleteIconColor: Theme.of(context).colorScheme.outline,
            ),
            InputChip(
              label: const Text('E-moll'),
              onDeleted: () {},
              deleteIconColor: Theme.of(context).colorScheme.outline,
            ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Hangnem hozzáadása'),
              onPressed: () {},
            ),
          ],
        ),
      ],
    );
  }
}
