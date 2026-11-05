import 'package:flutter/material.dart';

/// Shown in a filter card's chip row when the current query reaches no value for
/// that field, at chip-row height so the card does not resize.
class EmptyChipRow extends StatelessWidget {
  const EmptyChipRow({this.height = 42, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Nincs szűrhető dal.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
