import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/song/song.dart';
import '../../services/assets/get_song_asset.dart';

/// Resolves an attachment's bytes through the app's asset pipeline, waiting
/// for the download to finish (an already cached asset resolves immediately).
///
/// Resolves to null when [song] has no such attachment. Throws when the
/// download fails, so callers can log or skip it. Unlike
/// `ref.watch(getSongAssetProvider(...))` inside a callback, this does not
/// stop at the stream's first "starting download" event, so it also works for
/// assets that have not been downloaded yet.
Future<Uint8List?> fetchAssetBytes(WidgetRef ref, Song song, String field) {
  if (song.contentString(field) == null) {
    return Future<Uint8List?>.value(null);
  }

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

  // The stream reports progress first and the bytes last; guard against one
  // that never settles.
  return completer.future
      .timeout(const Duration(seconds: 30), onTimeout: () => null)
      .whenComplete(subscription.close);
}
