import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/log/logger.dart';
import '../../../services/app_links/navigation.dart';
import '../../../services/platform/platform_provider.dart';
import '../../../services/songs/bundle/import_bundle.dart';
import '../../../services/songs/bundle/song_bundle.dart';
import '../../../services/ui/messenger_service.dart';
import '../../cue/cue_page_type.dart';
import '../../cue/session/session_provider.dart';

/// Lets the user pick a `.sofar` file and imports it.
///
/// Mobile pickers cannot reliably filter by an unknown extension (iOS greys
/// the files out), so they accept any file and the content check does the
/// rest; desktop and web filter by extension.
Future<void> pickAndImportSongBundle(
  BuildContext context,
  WidgetRef ref,
) async {
  final platform = ref.read(platformInfoProvider);
  final messenger = ref.read(messengerServiceProviderProvider);

  Uint8List bytes;
  try {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Dalfájl importálása',
      type: platform.isMobile && !platform.isWeb
          ? FileType.any
          : FileType.custom,
      allowedExtensions: platform.isMobile && !platform.isWeb
          ? null
          : const [songBundleExtension],
    );
    if (file == null) return;
    bytes = await file.readAsBytes();
  } catch (e, s) {
    log.warning('A fájl kiválasztása nem sikerült', e, s);
    messenger.showSnackBar(
      const SnackBar(content: Text('Nem sikerült megnyitni a fájlt.')),
    );
    return;
  }
  if (!context.mounted) return;
  await importSongBundleFromBytes(context, ref, bytes);
}

/// Imports the song bundle [bytes]: reads and plans it, asks about conflicts,
/// applies it, reports the outcome and opens the imported song/cue.
///
/// Reusable entry point (file picker today, opening a `.sofar` file from the
/// OS later). Reports every problem itself; nothing is written when the file
/// is unreadable or the user cancels the choices dialog.
Future<void> importSongBundleFromBytes(
  BuildContext context,
  WidgetRef ref,
  Uint8List bytes,
) async {
  final messenger = ref.read(messengerServiceProviderProvider);

  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final ImportPlan plan;
  try {
    plan = await planSongBundleImport(bytes);
  } on UnsupportedBundleVersion {
    say(
      'Ez a fájl az alkalmazás újabb verziójával készült. Frissítsd az alkalmazást.',
    );
    return;
  } on SongBundleException catch (e) {
    log.info('Nem dalfájl: $e');
    say('Ez nem egy Sófár Hangoló dalfájl.');
    return;
  } catch (e, s) {
    log.warning('Az importálás előkészítése nem sikerült', e, s);
    say('Az importálás nem sikerült.');
    return;
  }

  if (plan.songs.isEmpty && plan.cue == null) {
    say('A fájl nem tartalmaz dalt.');
    return;
  }

  var choices = <String, ImportChoice>{};
  var cueChoice = CueImportChoice.keepBoth;
  if (plan.needingChoice.isNotEmpty || plan.existingCue != null) {
    if (!context.mounted) return;
    final decision = await showDialog<ImportDecision>(
      context: context,
      builder: (context) => ImportChoicesDialog(plan: plan),
    );
    if (decision == null) return; // cancelled: nothing is written
    choices = decision.choices;
    cueChoice = decision.cueChoice;
  }

  final ImportResult result;
  try {
    result = await applySongBundleImport(plan, choices, cueChoice: cueChoice);
  } catch (e, s) {
    log.severe('Az importálás nem sikerült', e, s);
    say('Az importálás nem sikerült, nem történt változás.');
    return;
  }

  // Report.
  final problems = [
    for (final d in result.droppedAttachments)
      '${_titleOf(plan, d.songUuid)}: ${d.field == 'pdf' ? 'PDF' : 'SVG'} csatolmány hibás, kihagytuk',
    for (final s in result.songs)
      if (s.action == ImportAction.skipped)
        '${s.title}: nem importálható${s.error == null ? '' : ' (${s.error})'}',
  ];
  final summary = importSummary(result);
  if (problems.isEmpty) {
    say(summary);
  } else if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importálás kész'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(summary),
              const SizedBox(height: 12),
              const Text('Figyelem:'),
              for (final p in problems) Text('• $p'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Rendben'),
          ),
        ],
      ),
    );
  }

  if (!context.mounted) return;
  await _openImported(context, ref, result);
}

String _titleOf(ImportPlan plan, String uuid) =>
    plan.songs.where((s) => s.uuid == uuid).firstOrNull?.title ?? 'Dal';

/// Opens the imported cue, or the song when the file held exactly one.
Future<void> _openImported(
  BuildContext context,
  WidgetRef ref,
  ImportResult result,
) async {
  final cue = result.cue;
  if (cue != null && cue.cue != null && cue.action != CueImportAction.skipped) {
    final session = ref.read(activeCueSessionProvider.notifier);
    final activeUuid = ref.read(activeCueSessionProvider).value?.cue.uuid;
    final uuid = cue.cue!.uuid;
    if (activeUuid == uuid) {
      // The cue on screen was overwritten: reload it.
      await session.load(uuid, forceReload: true);
    } else if (activeUuid != null) {
      await session.unload();
    }
    if (!context.mounted) return;
    context.push(cueRoutePath(uuid, CuePageType.edit));
    return;
  }

  if (cue == null && result.songs.length == 1) {
    final uuid = result.songs.single.resultingUuid;
    if (uuid != null) context.push(songRoutePath(uuid));
  }
}

/// One-line outcome of [result], e.g. "1 új dal, 1 másolat készült".
String importSummary(ImportResult result) {
  int count(ImportAction a) => result.songs.where((s) => s.action == a).length;
  final created = count(ImportAction.created);
  final updated = count(ImportAction.updated);
  final copies = count(ImportAction.createdCopy);
  final unchanged = count(ImportAction.unchanged);

  final parts = [
    if (created > 0) '$created új dal',
    if (updated > 0) '$updated dal frissítve',
    if (copies > 0) '$copies másolat készült',
    if (unchanged > 0) '$unchanged dal változatlan',
    if (result.cue != null)
      switch (result.cue!.action) {
        CueImportAction.created => 'új lista',
        CueImportAction.overwritten => 'lista felülírva',
        CueImportAction.createdCopy => 'lista másolata készült',
        CueImportAction.skipped => 'lista kihagyva',
      },
  ];
  return parts.isEmpty
      ? 'Nem volt mit importálni.'
      : 'Importálva: ${parts.join(', ')}.';
}

/// What the user decided in [ImportChoicesDialog].
class ImportDecision {
  const ImportDecision(this.choices, this.cueChoice);
  final Map<String, ImportChoice> choices;
  final CueImportChoice cueChoice;
}

String _choiceLabel(ImportChoice c) => switch (c) {
  ImportChoice.overwrite => 'Felülírás',
  ImportChoice.replace => 'Saját változatom cseréje',
  ImportChoice.keepBoth => 'Mindkettő megtartása',
};

String _explanation(PlannedSong s) => switch (s.outcome) {
  ImportOutcome.sibling =>
    'Ugyanebből a kottatári dalból neked is van saját változatod.',
  _ =>
    s.descendsFromOriginal
        ? 'A kapott változat az eredeti kottatári dalból készült, nem a te szerkesztésedből.'
        : 'Ezt a dalt te is szerkesztetted, és a kapott változat is eltér.',
};

/// Asks, per song that clashes with one already here (and for a cue that
/// exists already), what to do. Everything defaults to keeping both; Cancel
/// returns null and the import does not happen.
class ImportChoicesDialog extends StatefulWidget {
  const ImportChoicesDialog({super.key, required this.plan});

  final ImportPlan plan;

  @override
  State<ImportChoicesDialog> createState() => _ImportChoicesDialogState();
}

class _ImportChoicesDialogState extends State<ImportChoicesDialog> {
  late final Map<String, ImportChoice> _choices = {
    for (final s in widget.plan.needingChoice) s.uuid: ImportChoice.keepBoth,
  };
  CueImportChoice _cueChoice = CueImportChoice.keepBoth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingCue = widget.plan.existingCue;

    return AlertDialog(
      title: const Text('Mit tegyünk az ütköző dalokkal?'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final song in widget.plan.needingChoice) ...[
                Text(song.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(_explanation(song), style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final choice in song.choices)
                      ChoiceChip(
                        label: Text(_choiceLabel(choice)),
                        selected: _choices[song.uuid] == choice,
                        onSelected: (_) =>
                            setState(() => _choices[song.uuid] = choice),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (existingCue != null) ...[
                Text(
                  'Lista: ${existingCue.title}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Ez a lista már megvan nálad.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final (choice, label) in const [
                      (CueImportChoice.overwrite, 'Felülírás'),
                      (CueImportChoice.keepBoth, 'Mindkettő megtartása'),
                      (CueImportChoice.skip, 'Kihagyás'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _cueChoice == choice,
                        onSelected: (_) => setState(() => _cueChoice = choice),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Mégse'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(ImportDecision(_choices, _cueChoice)),
          child: const Text('Importálás'),
        ),
      ],
    );
  }
}
