import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/error/app_error.dart';
import 'card.dart';

import '../../base/home/parts/feedback/send_mail.dart';

class ErrorDialog extends StatelessWidget {
  const ErrorDialog({
    super.key,
    required this.type,
    required this.title,
    this.message,
    this.stack,
    required this.icon,
    this.showReportButton = true,
    this.onRetry,
    this.retryLabel,
  });

  factory ErrorDialog.fromAppError({
    Key? key,
    required AppError error,
    VoidCallback? onRetry,
    String? retryLabel,
    bool? showReportButton,
  }) {
    return ErrorDialog(
      key: key,
      type: switch (error.category) {
        AppErrorCategory.network => LErrorType.warning,
        AppErrorCategory.backend => LErrorType.error,
        AppErrorCategory.frontend => LErrorType.error,
      },
      title: error.title,
      message: error.userMessage,
      stack: error.stack,
      icon: switch (error.category) {
        AppErrorCategory.network => Icons.wifi_off,
        AppErrorCategory.backend => Icons.cloud_off,
        AppErrorCategory.frontend => Icons.bug_report,
      },
      showReportButton:
          showReportButton ?? error.category == AppErrorCategory.frontend,
      onRetry: onRetry,
      retryLabel: retryLabel,
    );
  }

  final LErrorType type;
  final String title;
  final String? message;
  final String? stack;
  final IconData icon;
  final bool showReportButton;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: LErrorCard(
        type: type,
        title: title,
        message: message,
        stack: stack,
        icon: icon,
        showReportButton: false,
      ),
      actions: [
        if (onRetry != null)
          FilledButton.icon(
            onPressed: onRetry,
            icon: Icon(Icons.refresh),
            label: Text(retryLabel ?? 'Újrapróbálás'),
          ),
        FilledButton.tonalIcon(
          onPressed: () => sendFeedbackEmail(
            errorMessage: '$title ($message)',
            stackTrace: stack,
          ),
          label: Text('Hibajelentés'),
          icon: Icon(Icons.feedback_outlined),
        ),
        FilledButton(onPressed: context.pop, child: Text('OK')),
      ],
    );
  }
}
