import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/bank/bank.dart';
import '../../../data/log/logger.dart';
import '../../../data/song/song.dart';
import '../../../services/assets/get_song_asset.dart';
import '../../../services/songs/original_status.dart';
import '../../../services/songs/write_song.dart';
import '../../common/confirm_dialog.dart';

/// Opens the song in the editor.
///
/// A local song edits in place. A bank-owned song cannot be edited directly,
/// so this first explains and confirms that a local copy will be made, then
/// edits the copy. When a copy already exists, the dialog also offers to edit
/// that one instead. The copy also gets its own copies of the original's
/// attachments (see [copySongToLocal]).
class EditSongButton extends StatelessWidget {
  const EditSongButton(this.song, {super.key});

  final Song song;

  bool get _isLocal => song.sourceBank == localBankUuid;

  @override
  Widget build(BuildContext context) {
    if (_isLocal) {
      return FilledButton.tonalIcon(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Szerkesztés'),
      );
    }
    return TextButton.icon(
      onPressed: () => _edit(context),
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Másolat szerkesztése'),
    );
  }

  Future<void> _edit(BuildContext context) async {
    if (_isLocal) {
      // Already on this song's page; the editor goes on top of it.
      context.push('/song/local/${song.uuid}');
      return;
    }

    final existingCopy = await localCopyOf(song);
    if (!context.mounted) return;

    Song? created;
    var editExisting = false;
    await showDialog<void>(
      context: context,
      builder: (context) => ConfirmDialog(
        title: 'Dal szerkesztése',
        message: existingCopy == null
            ? _newCopyMessage
            : _existingCopyMessage(existingCopy),
        actionLabel: 'Másolat szerkesztése',
        actionIcon: Icons.edit_outlined,
        actionOnPressed: () async {
          try {
            created = await copySongToLocal(song, fetchAsset: fetchSongAsset);
          } catch (error, stackTrace) {
            log.warning(
              'Nem sikerült helyi másolatot készíteni.',
              error,
              stackTrace,
            );
          }
        },
        primaryAction: existingCopy == null
            ? null
            : ConfirmDialogAction(
                label: 'Meglévő másolat szerkesztése',
                icon: Icons.edit_note_outlined,
                onPressed: () async => editExisting = true,
              ),
      ),
    );

    if (!context.mounted) return;
    final copy = editExisting ? existingCopy : created;
    if (copy == null) return;
    _openCopy(context, copy);
  }

  /// Opens [copy]'s own page with the editor on top, so going back from the
  /// editor lands on the edited copy.
  void _openCopy(BuildContext context, Song copy) {
    context.push('/song/${copy.uuid}');
    context.push('/song/local/${copy.uuid}');
  }

  static const _newCopyMessage =
      'Ez a dal egy daltárból származik, ezért nem szerkeszthető '
      'közvetlenül. A szerkesztéshez egy helyi másolat készül, ami a '
      '„Helyi dalok” közé kerül.\n\n'
      'A másolat független az eredetitől: a daltár frissítései nem '
      'írják felül.';

  String _existingCopyMessage(Song copy) {
    final name = copy.title == song.title ? '' : ': „${copy.title}”';
    return 'Ehhez a dalhoz már készült helyi másolat$name.\n\n'
        'Szerkesztheted a meglévőt, vagy készíthetsz egy új, független '
        'másolatot. A daltár frissítései a másolatokat nem írják felül.';
  }
}
