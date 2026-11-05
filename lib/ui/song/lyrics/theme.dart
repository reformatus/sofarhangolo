import 'package:flutter/material.dart';

/// Theme-level description of how the lyrics are drawn.
///
/// This keeps the lyrics widgets free of appearance branches: [VerseCard] just
/// reads the values, and the app theme decides whether lyrics get the usual
/// card-and-chip look or the flat, "Teljesen fekete háttér" look.
@immutable
class LyricsTheme extends ThemeExtension<LyricsTheme> {
  const LyricsTheme({
    required this.cardColor,
    required this.verseTagBackgroundColor,
    required this.verseTagForegroundColor,
    required this.verseTagFontWeight,
  });

  /// Background of a verse's card. Transparent in the flat look.
  final Color cardColor;

  /// Background of the verse tag chip, or null for no chip (flat look).
  final Color? verseTagBackgroundColor;

  /// Foreground color of the verse tag text.
  final Color verseTagForegroundColor;

  /// Weight of the verse tag text. Bold in the flat look.
  final FontWeight verseTagFontWeight;

  /// The default lyrics look: a raised card per verse with a colored tag chip.
  factory LyricsTheme.standard(ColorScheme colors) => LyricsTheme(
    cardColor: colors.onPrimary,
    verseTagBackgroundColor: colors.primary,
    verseTagForegroundColor: colors.onPrimary,
    verseTagFontWeight: FontWeight.normal,
  );

  /// The flat, "Teljesen fekete háttér" look: plain text on the app background,
  /// with the verse tag reduced to bold text.
  factory LyricsTheme.flat(ColorScheme colors) => LyricsTheme(
    cardColor: Colors.transparent,
    verseTagBackgroundColor: null,
    verseTagForegroundColor: colors.onSurface,
    verseTagFontWeight: FontWeight.bold,
  );

  @override
  LyricsTheme copyWith({
    Color? cardColor,
    Color? verseTagBackgroundColor,
    Color? verseTagForegroundColor,
    FontWeight? verseTagFontWeight,
  }) {
    return LyricsTheme(
      cardColor: cardColor ?? this.cardColor,
      verseTagBackgroundColor:
          verseTagBackgroundColor ?? this.verseTagBackgroundColor,
      verseTagForegroundColor:
          verseTagForegroundColor ?? this.verseTagForegroundColor,
      verseTagFontWeight: verseTagFontWeight ?? this.verseTagFontWeight,
    );
  }

  @override
  LyricsTheme lerp(covariant LyricsTheme? other, double t) {
    if (other == null) return this;
    return LyricsTheme(
      cardColor: Color.lerp(cardColor, other.cardColor, t)!,
      verseTagBackgroundColor: Color.lerp(
        verseTagBackgroundColor,
        other.verseTagBackgroundColor,
        t,
      ),
      verseTagForegroundColor: Color.lerp(
        verseTagForegroundColor,
        other.verseTagForegroundColor,
        t,
      )!,
      verseTagFontWeight: t < 0.5
          ? verseTagFontWeight
          : other.verseTagFontWeight,
    );
  }
}

extension LyricsThemeContext on BuildContext {
  LyricsTheme get lyricsTheme =>
      Theme.of(this).extension<LyricsTheme>() ??
      LyricsTheme.standard(Theme.of(this).colorScheme);
}
