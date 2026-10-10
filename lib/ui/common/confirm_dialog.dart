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

class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({
    required this.title,
    this.message,
    required this.actionLabel,
    required this.actionIcon,
    required this.actionOnPressed,
    this.dangerousAction = false,
    super.key,
  });

  final String title;

  /// Optional body explaining the action.
  final String? message;
  final String actionLabel;
  final IconData actionIcon;
  final Future Function() actionOnPressed;
  final bool dangerousAction;

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  bool isLoading = false;
  void onPressed() async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
    });
    // TODO try catch and show error
    await widget.actionOnPressed();
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: widget.message == null ? null : Text(widget.message!),
      actions: [
        if (widget.dangerousAction) ...[
          TextButton.icon(
            label: isLoading
                ? SizedBox(width: 60, child: LinearProgressIndicator())
                : Text(
                    widget.actionLabel,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall!.color,
                    ),
                  ),
            icon: IconTheme(
              data: IconThemeData(color: Colors.red),
              child: Icon(widget.actionIcon),
            ),
            onPressed: onPressed,
          ),
          FilledButton(
            onPressed: context.pop,
            autofocus: true,
            child: Text('Mégse'),
          ),
        ] else ...[
          FilledButton.tonal(onPressed: context.pop, child: Text('Mégse')),
          FilledButton.icon(
            onPressed: isLoading ? null : onPressed,
            label: isLoading
                ? SizedBox(width: 60, child: LinearProgressIndicator())
                : Text(widget.actionLabel),
            icon: Icon(widget.actionIcon),
            autofocus: true,
          ),
        ],
      ],
    );
  }
}
