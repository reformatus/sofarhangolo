import 'package:flutter/material.dart';

/// How loud a [LNoticeCard] is.
///
/// [info] takes the app's themed accent color, while [warning] and [error]
/// keep fixed orange/red so they read the same in every theme and stand apart
/// from the brand color.
enum LNoticeType { info, warning, error }

/// A boxed notice: an icon, a title, an optional body and optional actions.
///
/// This is the single implementation of the app's info/warning/error boxes —
/// [LErrorCard] is the error-specific wrapper around it — and it is what the
/// sidebars use for hints. Actions are laid out *inside* the box, spanning its
/// width, so a hint and the button that resolves it stay one unit instead of a
/// loose button hanging under a box.
class LNoticeCard extends StatelessWidget {
  const LNoticeCard({
    super.key,
    required this.type,
    required this.icon,
    required this.title,
    this.message,
    this.extraContent,
    this.actions = const <Widget>[],
    this.margin = EdgeInsets.zero,
  });

  final LNoticeType type;
  final IconData icon;
  final String title;

  /// Friendly body text; optional.
  final String? message;

  /// Extra widgets between the message and the actions (e.g. code boxes).
  final Widget? extraContent;

  /// Actions shown at the bottom of the box, full width, in order.
  final List<Widget> actions;

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (type) {
      LNoticeType.info => theme.colorScheme.primary,
      LNoticeType.warning => Colors.orange,
      LNoticeType.error => Colors.red,
    };

    return Card(
      margin: margin,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadiusGeometry.circular(18),
      ),
      color: Color.lerp(accent, theme.scaffoldBackgroundColor, 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(icon, color: accent.withAlpha(200)),
            title: Text(title, style: theme.textTheme.titleMedium),
            contentPadding: const EdgeInsets.only(left: 13, right: 8),
          ),
          if (message != null || extraContent != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  if (message != null) Text(message!),
                  ?extraContent,
                ],
              ),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: actions,
              ),
            ),
        ],
      ),
    );
  }
}
