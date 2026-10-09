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
    this.errorMessage,
    this.stack,
    required this.icon,
    this.showReportButton = true,
    this.onRetry,
    this.retryLabel,
  });

  factory ErrorDialog.fromAppError({
    Key? key,
    required AppError error,
    String? title,
    String? message,
    IconData? icon,
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
      title: title ?? error.title,
      message: message ?? error.userMessage,
      errorMessage: error.details,
      stack: error.stack,
      icon:
          icon ??
          switch (error.category) {
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

  /// Friendly body text; optional.
  final String? message;

  /// Technical failure, rendered in a code box; optional.
  final String? errorMessage;

  /// Stack trace, rendered in a code box; optional.
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
        errorMessage: errorMessage,
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
        if (showReportButton)
          FilledButton.tonalIcon(
            onPressed: () => sendFeedbackEmail(
              errorMessage: [
                title,
                if (message != null) message,
                if (errorMessage != null) errorMessage,
              ].join('\n'),
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
