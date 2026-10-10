import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/bank/bank.dart';
import '../../../data/log/logger.dart';
import '../../../data/song/song.dart';
import '../../../services/assets/get_song_asset.dart';
import '../../../services/songs/write_song.dart';
import '../../common/confirm_dialog.dart';

/// Opens the song in the editor.
///
/// A local song edits in place. A bank-owned song cannot be edited directly,
/// so this first explains and confirms that a local copy will be made, then
/// edits the copy. The copy also gets its own copies of the original's
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
      context.push('/song/local/${song.uuid}');
      return;
    }

    Song? copy;
    await showDialog<void>(
      context: context,
      builder: (context) => ConfirmDialog(
        title: 'Dal szerkesztése',
        message:
            'Ez a dal egy daltárból származik, ezért nem szerkeszthető '
            'közvetlenül. A szerkesztéshez egy helyi másolat készül, ami a '
            '„Helyi dalok” közé kerül.\n\n'
            'A másolat független az eredetitől: a daltár frissítései nem '
            'írják felül.',
        actionLabel: 'Másolat szerkesztése',
        actionIcon: Icons.edit_outlined,
        actionOnPressed: () async {
          try {
            copy = await copySongToLocal(song, fetchAsset: fetchSongAsset);
          } catch (error, stackTrace) {
            log.warning(
              'Nem sikerült helyi másolatot készíteni.',
              error,
              stackTrace,
            );
          }
        },
      ),
    );

    final created = copy;
    if (created == null || !context.mounted) return;
    // Put the copy's page under the editor, so going back from the editor
    // lands on the freshly created (and edited) copy rather than the original.
    context.push('/song/${created.uuid}');
    context.push('/song/local/${created.uuid}');
  }
}
