import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/song/lyrics/format.dart';
import '../../../data/song/lyrics/parser.dart';
import '../../../data/song/song.dart';
import '../../../data/song/transpose.dart';
import '../../common/adaptive_page/page.dart';
import '../lyrics/view.dart';

/// Which representation of the song is being edited — mirrors the content
/// kinds a song page can show (lyrics, sheet SVG, sheet PDF).
enum _ContentTab { lyrics, svg, pdf }

/// Mock of the local song editor (Phase B wireframe).
///
/// All data is hardcoded and nothing is persisted — this exists to shape
/// the UX before any logic is wired up.
class LocalSongEditPage extends ConsumerStatefulWidget {
  const LocalSongEditPage({super.key});

  @override
  ConsumerState<LocalSongEditPage> createState() => _LocalSongEditPageState();
}

class _LocalSongEditPageState extends ConsumerState<LocalSongEditPage> {
  static final Song _mockSong = Song(
    uuid: 'mock-local-song',
    title: 'Áldjad, én lelkem, az Urat',
    lyrics: _mockLyrics,
    lyricsFormat: LyricsFormat.opensong,
    keyField: [KeyField('C', 'major')],
    contentMap: {'svg': 'local://mock-svg-reference'},
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

  _ContentTab _activeContent = _ContentTab.lyrics;

  @override
  void dispose() {
    _titleController.dispose();
    _lyricsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptivePage(
      title: 'Dal szerkesztése',
      titleWidget: TextField(
        controller: _titleController,
        style: Theme.of(context).appBarTheme.titleTextStyle,
        decoration: const InputDecoration.collapsed(hintText: 'Dal címe'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<_ContentTab>(
              segments: const [
                ButtonSegment(
                  value: _ContentTab.lyrics,
                  icon: Icon(Icons.notes),
                  label: Text('Dalszöveg'),
                ),
                ButtonSegment(
                  value: _ContentTab.svg,
                  icon: Icon(Icons.image_outlined),
                  label: Text('SVG kotta'),
                ),
                ButtonSegment(
                  value: _ContentTab.pdf,
                  icon: Icon(Icons.picture_as_pdf_outlined),
                  label: Text('PDF'),
                ),
              ],
              selected: {_activeContent},
              onSelectionChanged: (selection) =>
                  setState(() => _activeContent = selection.first),
            ),
          ),
          Expanded(
            child: switch (_activeContent) {
              _ContentTab.lyrics => _LyricsEditor(
                controller: _lyricsController,
              ),
              _ContentTab.svg => const _AttachmentEditor(
                icon: Icons.image_outlined,
                title: 'SVG kotta',
                attached: true,
              ),
              _ContentTab.pdf => const _AttachmentEditor(
                icon: Icons.picture_as_pdf_outlined,
                title: 'PDF kotta',
                attached: false,
              ),
            },
          ),
        ],
      ),
      leftDrawer: const _DetailsPane(),
      leftDrawerIcon: Icons.info_outline,
      leftDrawerTooltip: 'Részletek',
      rightDrawer: _PreviewPane(content: _activeContent),
      rightDrawerIcon: Icons.visibility_outlined,
      rightDrawerTooltip: 'Előnézet',
      actionBarChildren: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.save_outlined),
            label: const Text('Mentés'),
          ),
        ),
      ],
      appBarActions: [
        PopupMenuButton<String>(
          tooltip: 'További műveletek',
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Dal törlése'),
                iconColor: Colors.red,
                textColor: Colors.red,
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _LyricsEditor extends StatelessWidget {
  const _LyricsEditor({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          const Text(
            'OpenSong formátum: [Verze]/[Refrén] szakaszok, a . kezdetű sorok akkordokat tartalmaznak.',
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
          TextField(
            controller: controller,
            maxLines: 24,
            minLines: 12,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '[Verze]\n.  Akkordok\n Dalszöveg…',
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared editor surface for sheet attachments (SVG and PDF get the same
/// treatment: a preview frame when attached, an attach call-to-action when
/// not).
class _AttachmentEditor extends StatelessWidget {
  const _AttachmentEditor({
    required this.icon,
    required this.title,
    required this.attached,
  });

  final IconData icon;
  final String title;
  final bool attached;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (attached) ...[
            Container(
              height: 260,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    Icon(icon, size: 48, color: colors.outline),
                    Text(
                      'Csatolmány feltöltve',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () {},
                  icon: const Icon(Icons.sync),
                  label: const Text('Csere'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                  ),
                  onPressed: () {},
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eltávolítás'),
                ),
              ],
            ),
          ] else
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  spacing: 8,
                  children: [
                    Icon(icon, size: 48, color: colors.outline),
                    Text('Még nincs $title csatolva'),
                    FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Fájl csatolása'),
                    ),
                  ],
                ),
              ),
            ),
        ],
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

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.content});

  final _ContentTab content;

  @override
  Widget build(BuildContext context) {
    final verses = content == _ContentTab.lyrics
        ? LyricsParser.forFormat(
            _LocalSongEditPageState._mockSong.lyricsFormat,
          ).parse(_LocalSongEditPageState._mockLyrics)
        : const [];

    return LayoutBuilder(
      builder: (context, constraints) {
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
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Előnézet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (content) {
                _ContentTab.lyrics => SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    direction: Axis.vertical,
                    children: [
                      ...verses.indexed.map(
                        (entry) => SizedBox(
                          width: verseWidth,
                          child: VerseCard(
                            _LocalSongEditPageState._mockSong,
                            entry.$2 as OpenSongVerse,
                            transpose: SongTranspose(),
                            verseIndex: entry.$1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _ContentTab.svg || _ContentTab.pdf => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      Icon(
                        content == _ContentTab.svg
                            ? Icons.image_outlined
                            : Icons.picture_as_pdf_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      Text(
                        content == _ContentTab.svg
                            ? 'SVG előnézet'
                            : 'PDF előnézet',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              },
            ),
          ],
        );
      },
    );
  }
}
