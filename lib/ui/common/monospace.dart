import 'package:flutter/material.dart';

/// Primary monospace family.
///
/// On Linux fontconfig aliases `Courier New` to a monospace substitute
/// (usually Liberation Mono), and it exists on macOS and Windows. The
/// generic `monospace` family is deliberately *not* the primary: on some
/// Linux setups fontconfig resolves it to a proportional font, and
/// [TextStyle.fontFamilyFallback] is only consulted for glyphs the primary
/// family lacks, so a resolveable-but-wrong primary would defeat the
/// fallback entirely.
const String monospaceFontFamily = 'Courier New';

/// Families used when [monospaceFontFamily] is not installed, per platform.
const List<String> monospaceFontFamilyFallback = [
  'monospace', // Android, web
  'Menlo', // iOS, macOS
  'Consolas', // Windows
  'DejaVu Sans Mono', // Linux
  'Liberation Mono', // Linux (fontconfig's usual Courier New substitute)
];

/// Base monospace [TextStyle]; use `.copyWith` for size, height and color.
const TextStyle monospaceTextStyle = TextStyle(
  fontFamily: monospaceFontFamily,
  fontFamilyFallback: monospaceFontFamilyFallback,
);
