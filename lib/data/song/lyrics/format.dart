import 'package:drift/drift.dart';

/// Supported lyrics formats for songs.
///
/// Each format has a corresponding [LyricsParser] implementation that handles
/// parsing and rendering of the lyrics content.
enum LyricsFormat {
  /// OpenSong format - uses brackets for sections, dots for chord lines.
  /// See: http://www.opensong.org/
  opensong('opensong'),

  /// ChordPro format - uses inline bracket chords and brace directives.
  /// See: https://www.chordpro.org/
  chordpro('chordpro');

  final String value;
  const LyricsFormat(this.value);

  /// Parse from string value (e.g., from JSON or database).
  /// Returns [opensong] as default if value is null or unrecognized.
  static LyricsFormat fromString(String? value) {
    if (value == null) return LyricsFormat.opensong;
    return LyricsFormat.values.firstWhere(
      (e) => e.value == value,
      orElse: () => LyricsFormat.opensong,
    );
  }
}

/// Type converter for storing [LyricsFormat] in Drift database.
class LyricsFormatConverter extends TypeConverter<LyricsFormat, String> {
  const LyricsFormatConverter();

  @override
  LyricsFormat fromSql(String fromDb) {
    return LyricsFormat.fromString(fromDb);
  }

  @override
  String toSql(LyricsFormat value) {
    return value.value;
  }
}
