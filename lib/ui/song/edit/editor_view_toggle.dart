import 'package:flutter/material.dart';

/// Edit/preview switch for the tabbed lyrics layout.
///
/// Two separate buttons styled like the sheet attachment actions (filled
/// tonal when active, outlined otherwise). When [compact] (mobile) the
/// selected one drops its label.
class EditorViewToggle extends StatelessWidget {
  const EditorViewToggle({
    super.key,
    required this.selectedIndex,
    required this.compact,
    required this.onChanged,
  });

  /// 0 = edit, 1 = preview.
  final int selectedIndex;

  /// Whether the selected button should drop its label (mobile).
  final bool compact;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          index: 0,
          icon: Icons.edit_outlined,
          label: 'Szerkesztés',
        ),
        const SizedBox(width: 8),
        _button(
          index: 1,
          icon: Icons.visibility_outlined,
          label: 'Előnézet',
        ),
      ],
    );
  }

  Widget _button({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = selectedIndex == index;
    void onPressed() => onChanged(index);
    final showLabel = !(compact && selected);
    final labelWidget = Text(
      label,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );

    if (selected) {
      return showLabel
          ? FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: labelWidget,
            )
          : FilledButton.tonal(onPressed: onPressed, child: Icon(icon));
    }
    return showLabel
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: labelWidget,
          )
        : OutlinedButton(onPressed: onPressed, child: Icon(icon));
  }
}
