import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sofarhangolo/data/log/logger.dart';
import 'package:sofarhangolo/data/song/extensions.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/assets/get_song_asset.dart';
import 'package:sofarhangolo/services/text_export/song_lyrics.dart';

/// Shares the song's lyrics in the user-friendly text representation
/// (pretty verse headers, no chords) via the system share sheet.
Future<void> shareLyricsText(Song song) async {
  if (!song.hasLyrics) return;
  await SharePlus.instance.share(
    ShareParams(text: friendlySongLyricsOf(song).text),
  );
}

/// Shares the song's lyrics in their original, unprocessed source format
/// via the system share sheet.
Future<void> shareRawLyrics(Song song) async {
  final lyrics = song.lyrics;
  if (lyrics == null || lyrics.isEmpty) return;
  await SharePlus.instance.share(ShareParams(text: lyrics));
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
      } else {
        log.warning('Üres file');
      }
    case AsyncLoading():
  }
}
