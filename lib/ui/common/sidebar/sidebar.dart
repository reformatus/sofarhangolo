import 'package:flutter/material.dart';

/// The vertical stack a sidebar lays its content out with.
///
/// Children span the sidebar's full width, which is what makes the buttons
/// inside a sidebar fill it instead of hugging their label — the rule for
/// every sidebar in the app (song, song editor, cue editor).
class SidebarColumn extends StatelessWidget {
  const SidebarColumn({super.key, required this.children, this.gap = 8});

  final List<Widget> children;

  /// Vertical space between the children; [SidebarDivider]s included.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gap,
      children: children,
    );
  }
}

/// Subtle separator between the semantic groups of a sidebar.
///
/// [SidebarColumn] already spaces it, so this only draws the line itself.
class SidebarDivider extends StatelessWidget {
  const SidebarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
