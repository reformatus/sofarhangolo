import 'lyrics/parser.dart';
import 'song.dart';

extension PropertyUtils on Song {
  bool get hasSvg => contentMap['svg']?.isNotEmpty ?? false;

  bool get hasPdf => contentMap['pdf']?.isNotEmpty ?? false;

  bool get hasLyrics => lyrics.isNotEmpty;

  /// Check if lyrics contain chord annotations using the appropriate parser.
  bool get hasChords =>
      hasLyrics &&
      LyricsParser.forFormat(
        lyricsFormat,
      ).hasChords(lyrics, presentationOrder: presentationOrder);

  List<String> get availableViews => [
    if (hasSvg) 'svg',
    if (hasPdf) 'pdf',
    if (hasLyrics) 'lyrics',
    if (hasChords) 'chords',
  ];
}
