import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/bank/bank.dart';
import '../../../data/log/logger.dart';
import '../../../data/song/song.dart';
import '../../../services/songs/write_song.dart';
import '../../common/confirm_dialog.dart';

/// Opens the song in the editor.
///
/// A local song edits in place. A bank-owned song cannot be edited directly,
/// so this first explains and confirms that a local copy will be made, then
/// edits the copy.
class EditSongButton extends StatelessWidget {
  const EditSongButton(this.song, {super.key});

  final Song song;

  bool get _isLocal => song.sourceBank == localBankUuid;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _edit(context),
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Szerkesztés'),
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
            'Ez a dal egy táblából származik, ezért nem szerkeszthető '
            'közvetlenül. A szerkesztéshez egy helyi másolat készül, ami a '
            '„Helyi dalok” közé kerül.\n\n'
            'A másolat független az eredetitől: a tábla frissítései nem '
            'írják felül. Az eredetit továbbra is figyeljük, és jelezzük, '
            'ha eltér a másolattól.',
        actionLabel: 'Másolat szerkesztése',
        actionIcon: Icons.edit_outlined,
        actionOnPressed: () async {
          try {
            copy = await copySongToLocal(song);
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
    context.push('/song/local/${created.uuid}');
  }
}
