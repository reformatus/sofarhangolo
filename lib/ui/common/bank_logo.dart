import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A bank's identifying mark: its downloaded logo image, or a fallback [icon]
/// for banks without one, like the local bank.
///
/// Always occupies a [size]×[size] square: logos scale down into it (small
/// images are not blown up), the fallback icon fills it.
class BankLogo extends StatelessWidget {
  const BankLogo({
    super.key,
    this.image,
    this.size = 24,
    this.icon = Icons.library_music,
    this.color,
  });

  /// The bank's logo bytes; null shows [icon] instead.
  final Uint8List? image;

  /// Side of the square the mark occupies.
  final double size;

  /// Icon shown when the bank has no [image].
  final IconData icon;

  /// Color of the fallback icon; null uses the theme's icon color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    return SizedBox.square(
      dimension: size,
      child: image != null
          ? Image.memory(image)
          : FittedBox(child: Icon(icon, color: color)),
    );
  }
}
