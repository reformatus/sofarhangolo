import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
class EditSongButton extends ConsumerWidget {
  const EditSongButton(this.song, {super.key});

  final Song song;

  bool get _isLocal => song.sourceBank == localBankUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => _edit(context, ref),
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Szerkesztés'),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
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
            copy = await copySongToLocal(
              song,
              fetchAsset: (song, field) => _fetchAssetBytes(ref, song, field),
            );
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

  /// Reads an attachment's bytes through the app's asset pipeline, downloading
  /// and caching it on demand.
  Future<Uint8List?> _fetchAssetBytes(
    WidgetRef ref,
    Song song,
    String field,
  ) {
    final completer = Completer<Uint8List?>();
    final subscription = ref.listenManual<AsyncValue<AssetResult>>(
      getSongAssetProvider(song, field),
      (previous, next) {
        if (completer.isCompleted) return;
        next.when(
          data: (result) {
            if (result.data != null) completer.complete(result.data);
          },
          error: completer.completeError,
          loading: () {},
        );
      },
      fireImmediately: true,
    );

    // `getSongAsset` emits a "loading" event first and then the bytes; guard
    // against a stream that never settles.
    return completer.future
        .timeout(const Duration(seconds: 30), onTimeout: () => null)
        .whenComplete(subscription.close);
  }
}
