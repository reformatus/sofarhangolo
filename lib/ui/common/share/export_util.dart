import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sofarhangolo/data/log/logger.dart';
import 'package:sofarhangolo/data/song/extensions.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/text_export/song_lyrics.dart';
import 'package:sofarhangolo/ui/common/asset_bytes.dart';

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

/// Shares the song's PDF sheet music via the system share sheet.
///
/// Awaits the asset download through [fetchAssetBytes], so sharing works for
/// PDFs that have not been downloaded yet. Does nothing when the song has no
/// PDF or the download fails.
Future<void> sharePdf(Song song, WidgetRef ref) async {
  if (song.pdfRef == null) return;

  try {
    final bytes = await fetchAssetBytes(ref, song, 'pdf');
    if (bytes == null) {
      log.warning('Nem sikerült letölteni a PDF-et a megosztáshoz.');
      return;
    }

    // TODO not supported on linux, download it to a selectable location
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes)],
        fileNameOverrides: ['${song.title}.pdf'],
      ),
    );
  } catch (error, stackTrace) {
    log.warning('Letöltés közben hiba lépett fel', error, stackTrace);
  }
}
