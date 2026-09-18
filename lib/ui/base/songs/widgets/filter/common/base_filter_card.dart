import 'package:flutter/material.dart';

/// A reusable base filter card layout that provides consistent styling and structure
/// for different types of filter widgets.
class BaseFilterCard extends StatelessWidget {
  const BaseFilterCard({
    required this.icon,
    required this.title,
    this.child,
    this.onResetPressed,
    this.trailing,
    this.isActive = false,
    super.key,
  });

  /// The icon to display when the filter is not active
  final IconData icon;

  /// The title text for the filter
  final String title;

  /// The widget to display in the subtitle area (typically filter content)
  final Widget? child;

  /// Callback when the reset (X) button is pressed. If null, no reset button is shown.
  final VoidCallback? onResetPressed;

  /// Optional trailing widget (e.g., count text)
  final Widget? trailing;

  /// Whether this filter is currently active (has selections)
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isActive ? 3 : 0,
      color: isActive ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: !isActive
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(icon),
              )
            : SizedBox(
                width: 32,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onResetPressed,
                  icon: const Icon(Icons.clear),
                ),
              ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(title),
            if (trailing != null) Expanded(child: trailing!),
          ],
        ),
        subtitle: child,
      ),
    );
  }
}
