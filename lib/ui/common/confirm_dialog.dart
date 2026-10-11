import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Future showConfirmDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required IconData actionIcon,
  required Future Function() actionOnPressed,
  String? message,
  bool dangerousAction = false,
  Key? key,
}) async {
  return await showDialog(
    context: context,
    builder: (context) => ConfirmDialog(
      title: title,
      message: message,
      actionLabel: actionLabel,
      actionIcon: actionIcon,
      actionOnPressed: actionOnPressed,
    ),
  );
}

/// One action of a [ConfirmDialog], usable as its primary action.
class ConfirmDialogAction {
  const ConfirmDialogAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Future Function() onPressed;
}

class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({
    required this.title,
    this.message,
    required this.actionLabel,
    required this.actionIcon,
    required this.actionOnPressed,
    this.primaryAction,
    this.dangerousAction = false,
    super.key,
  });

  final String title;

  /// Optional body explaining the action.
  final String? message;
  final String actionLabel;
  final IconData actionIcon;
  final Future Function() actionOnPressed;

  /// When set, this becomes the dialog's primary (filled, autofocused) action
  /// and [actionLabel]/[actionOnPressed] are demoted to a plain text button.
  final ConfirmDialogAction? primaryAction;

  final bool dangerousAction;

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  bool isLoading = false;

  Future<void> _run(Future Function() action) async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
    });
    // TODO try catch and show error
    await action();
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    context.pop();
  }

  Widget _actionLabel(String label) => isLoading
      ? SizedBox(width: 60, child: LinearProgressIndicator())
      : Text(label);

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryAction;

    return AlertDialog(
      title: Text(widget.title),
      content: widget.message == null ? null : Text(widget.message!),
      actions: [
        if (widget.dangerousAction) ...[
          TextButton.icon(
            label: _actionLabel(widget.actionLabel),
            icon: IconTheme(
              data: IconThemeData(color: Colors.red),
              child: Icon(widget.actionIcon),
            ),
            onPressed: () => _run(widget.actionOnPressed),
          ),
          FilledButton(
            onPressed: context.pop,
            autofocus: true,
            child: Text('Mégse'),
          ),
        ] else ...[
          FilledButton.tonal(onPressed: context.pop, child: Text('Mégse')),
          if (primary != null)
            TextButton.icon(
              onPressed: isLoading ? null : () => _run(widget.actionOnPressed),
              label: _actionLabel(widget.actionLabel),
              icon: Icon(widget.actionIcon),
            ),
          if (primary == null)
            FilledButton.icon(
              onPressed: isLoading ? null : () => _run(widget.actionOnPressed),
              label: _actionLabel(widget.actionLabel),
              icon: Icon(widget.actionIcon),
              autofocus: true,
            )
          else
            FilledButton.icon(
              onPressed: isLoading ? null : () => _run(primary.onPressed),
              label: Text(primary.label),
              icon: Icon(primary.icon),
              autofocus: true,
            ),
        ],
      ],
    );
  }
}
