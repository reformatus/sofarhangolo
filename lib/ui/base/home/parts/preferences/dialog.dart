import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../config/config.dart';
import '../../../../../services/preferences/preferences_parent.dart';
import '../../../../../services/preferences/providers/general.dart';
import '../../../../../services/preferences/providers/lyrics_view_style.dart';
import '../../../../../services/preferences/providers/song_view_order.dart';
import '../../../../song/state.dart';
import '../about.dart';

class PreferencesDialog extends ConsumerStatefulWidget {
  const PreferencesDialog({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<PreferencesDialog> {
  late ScrollController bodyController;

  @override
  void initState() {
    bodyController = ScrollController();
    super.initState();
  }

  // TODO factor out each section into separate widgets
  @override
  Widget build(BuildContext context) {
    final general = ref.watch(generalPreferencesProvider);
    final lyricsView = ref.watch(lyricsViewStylePreferencesProvider);
    final songViewOrder = (ref.watch(
      songViewOrderPreferencesProvider,
    )).songViewOrder;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: appConfig.breakpoints.tabletFromWidth,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: Text('Beállítások'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(onPressed: context.pop, icon: Icon(Icons.close)),
              ],
              actionsPadding: EdgeInsets.only(right: 8),
            ),
            Expanded(
              child: Container(
                color: Theme.of(context).colorScheme.surface,
                padding: EdgeInsets.only(left: 16, right: 16, bottom: 16),
                child: FadingEdgeScrollView.fromSingleChildScrollView(
                  child: SingleChildScrollView(
                    controller: bodyController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        sectionTitle('Színek'),
                        settingTitle('ALKALMAZÁS'),
                        SegmentedButton<ThemeMode>(
                          segments: ThemeMode.values
                              .map(
                                (v) => ButtonSegment(
                                  value: v,
                                  label: Text(v.title),
                                ),
                              )
                              .toList(),
                          selected: {general.appBrightness},
                          showSelectedIcon:
                              MediaQuery.of(context).size.width < 400
                              ? false
                              : true,
                          multiSelectionEnabled: false,
                          onSelectionChanged: (selection) => ref
                              .read(generalPreferencesProvider.notifier)
                              .setAppBrightness(selection.first),
                        ),
                        if (Theme.brightnessOf(context) == Brightness.dark ||
                            (MediaQuery.platformBrightnessOf(context) ==
                                    Brightness.dark &&
                                general.sheetBrightness == ThemeMode.system) ||
                            general.sheetBrightness == ThemeMode.dark)
                          Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: CheckboxListTile(
                              value: general.oledBlackBackground,
                              onChanged: (newValue) => ref
                                  .read(generalPreferencesProvider.notifier)
                                  .setOledBlackBackground(newValue ?? false),
                              title: Text('Teljesen fekete háttér'),
                            ),
                          ),

                        Padding(
                          padding: EdgeInsetsGeometry.only(bottom: 3, top: 15),
                          child: Row(
                            children: [
                              Text(
                                'KOTTA',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              SizedBox(width: 4),
                              Badge(
                                label: Text('Kísérleti'),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                        SegmentedButton<ThemeMode>(
                          segments: ThemeMode.values
                              .map(
                                (v) => ButtonSegment(
                                  value: v,
                                  label: Text(v.title),
                                ),
                              )
                              .toList(),
                          selected: {general.sheetBrightness},
                          multiSelectionEnabled: false,
                          showSelectedIcon:
                              MediaQuery.of(context).size.width < 400
                              ? false
                              : true,
                          onSelectionChanged: (selection) => ref
                              .read(generalPreferencesProvider.notifier)
                              .setSheetBrightness(selection.first),
                        ),
                        Divider(height: 45, thickness: 2),
                        sectionTitle('Alapértelmezett nézet'),
                        Text(
                          'Rendezd prioritási sorrendbe a dalnézeteket. Az első elérhető nézettel fog megnyílni minden dal első megnyitáskor.',
                        ),
                        SizedBox(height: 8),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          itemCount: songViewOrder.length,
                          physics: NeverScrollableScrollPhysics(),
                          itemBuilder: (context, index) => IntrinsicHeight(
                            key: Key(songViewOrder[index].name),
                            child: ListTile(
                              leading: Icon(switch (songViewOrder[index]) {
                                SongViewType.svg => Icons.music_note_outlined,
                                SongViewType.pdf => Icons.audio_file_outlined,
                                SongViewType.lyrics =>
                                  Icons.text_snippet_outlined,
                                SongViewType.chords => Icons.tag_outlined,
                              }),
                              title: Text(switch (songViewOrder[index]) {
                                SongViewType.svg => 'Kotta',
                                SongViewType.pdf => 'PDF',
                                SongViewType.lyrics => 'Dalszöveg',
                                SongViewType.chords => 'Akkordos dalszöveg',
                              }),
                              trailing: ReorderableDragStartListener(
                                index: index,
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                          ),
                          onReorder: (oldIndex, newIndex) => ref
                              .read(songViewOrderPreferencesProvider.notifier)
                              .reorder(oldIndex, newIndex),
                        ),
                        Divider(height: 45, thickness: 2),
                        Row(
                          children: [
                            sectionTitle('Dalszöveg és akkordok'),
                            IconButton(
                              onPressed: () => ref
                                  .read(
                                    lyricsViewStylePreferencesProvider.notifier,
                                  )
                                  .reset(),
                              icon: Icon(Icons.replay),
                              visualDensity: VisualDensity.compact,
                              iconSize: 18,
                              tooltip: 'Visszaállítás',
                            ),
                          ],
                        ),
                        settingTitle(
                          'Versszakszám mérete - ${lyricsView.verseTagSize.truncate()}',
                        ),
                        Slider(
                          value: lyricsView.verseTagSize,
                          onChanged: (newValue) => ref
                              .read(lyricsViewStylePreferencesProvider.notifier)
                              .setVerseTagSize(newValue),
                          min: 4,
                          max: 50,
                        ),
                        settingTitle(
                          'Akkordok mérete - ${lyricsView.chordsSize.truncate()}',
                        ),
                        Slider(
                          value: lyricsView.chordsSize,
                          onChanged: (newValue) => ref
                              .read(lyricsViewStylePreferencesProvider.notifier)
                              .setChordsSize(newValue),
                          min: 4,
                          max: 50,
                        ),
                        settingTitle(
                          'Dalszöveg mérete - ${lyricsView.lyricsSize.truncate()}',
                        ),
                        Slider(
                          value: lyricsView.lyricsSize,
                          onChanged: (newValue) => ref
                              .read(lyricsViewStylePreferencesProvider.notifier)
                              .setLyricsSize(newValue),
                          min: 4,
                          max: 50,
                        ),
                        settingTitle(
                          'Oszlopszélesség - ${lyricsView.verseCardColumnWidth}',
                        ),
                        Slider(
                          value: lyricsView.verseCardColumnWidth.toDouble(),
                          onChanged: (newValue) => ref
                              .read(lyricsViewStylePreferencesProvider.notifier)
                              .setVerseCardColumnWidth(newValue.round()),
                          min: 70,
                          max: 700,
                        ),
                        Divider(height: 45, thickness: 2),
                        TextButton.icon(
                          onPressed: () => showLyricAboutDialog(context),
                          label: Text('Névjegy'),
                          icon: Icon(Icons.info_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: EdgeInsetsGeometry.only(bottom: 5),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget settingTitle(String title) {
    return Padding(
      padding: EdgeInsetsGeometry.only(bottom: 3, top: 12),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
