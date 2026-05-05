import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sofarhangolo/data/log/logger.dart';
import 'package:sofarhangolo/data/song/lyrics/parser.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/assets/get_song_asset.dart';

Future<void> copyLyricsText(Song song) async {
  await SharePlus.instance.share(
    ShareParams(
      text: LyricsParser.forFormat(song.lyricsFormat).getText(song.lyrics),
    ),
  );
}

Future<void> copyLyrics(Song song) async {
  await SharePlus.instance.share(ShareParams(text: song.lyrics));
}

Future<void> getPDF(Song song, WidgetRef ref) async {
  final assetProvider = getSongAssetProvider(song, 'pdf');
  final asset = ref.watch(assetProvider);
  // TODO show loading
  switch (asset) {
    case AsyncError(:final error, :final stackTrace):
      log.warning('Letöltés közben hiba lépett fel', error, stackTrace);
    case AsyncData(value: final assetResult):
      if (assetResult.data != null) {
        try {
          // TODO not supported on linux, download it to a selectable location
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile.fromData(assetResult.data!)],
              fileNameOverrides: ['${song.title}.pdf'],
            ),
          );
        } catch (error, stackTrace) {
          log.warning('Letöltés közben hiba lépett fel', error, stackTrace);
        }
      }
      log.warning('Üres file');
    case AsyncLoading():
  }
}
