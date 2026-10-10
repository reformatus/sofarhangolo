import 'package:flutter/material.dart';

/// A row of placeholder chips shown while a filter's values load.
///
/// It mirrors the real chip row's height and rough chip size, so the card does
/// not change height (or shift the cards below it) when the values arrive.
class SkeletonChipRow extends StatelessWidget {
  const SkeletonChipRow({
    this.height = 42,
    this.widths = const [72, 96, 64],
    super.key,
  });

  /// Height of the row, matching the real chip row.
  final double height;

  /// Placeholder chip widths, roughly what the real labels occupy.
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final width in widths)
              Padding(
                padding: const EdgeInsets.only(right: 5, left: 2),
                child: Container(
                  width: width,
                  height: height - 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
