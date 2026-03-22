import 'package:flutter/material.dart';

import '../../../services/error/app_error.dart';
import '../../base/home/parts/feedback/send_mail.dart';

class LErrorCard extends StatelessWidget {
  const LErrorCard({
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

  factory LErrorCard.fromAppError({
    Key? key,
    required AppError error,
    VoidCallback? onRetry,
    String? retryLabel,
    bool? showReportButton,
  }) {
    return LErrorCard(
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
    return Padding(
      padding: EdgeInsets.all(10),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadiusGeometry.circular(18),
        ),
        color: Color.lerp(
          switch (type) {
            LErrorType.error => Colors.red,
            LErrorType.warning => Colors.orange,
            LErrorType.info => Colors.blue,
          },
          Theme.of(context).scaffoldBackgroundColor,
          0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(
                icon,
                color: switch (type) {
                  LErrorType.error => Colors.red,
                  LErrorType.warning => Colors.orange,
                  LErrorType.info => Colors.blue,
                }.withAlpha(200),
              ),
              title: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),

              contentPadding: EdgeInsets.only(left: 13, right: 8),
            ),
            if (message != null || stack != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (message != null) Text(message!),
                    if (stack != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: 100),
                        child: SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              stack!,
                              style: TextStyle(
                                fontFamily: 'Courier New',
                              ), // todo is available on android?
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (onRetry != null)
              Padding(
                padding: EdgeInsetsGeometry.only(left: 8, right: 8, bottom: 8),
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: Icon(Icons.refresh),
                  label: Text(retryLabel ?? 'Újra'),
                ),
              ),
            if (showReportButton)
              Padding(
                padding: EdgeInsetsGeometry.all(8),
                child: FilledButton.icon(
                  onPressed: () => sendFeedbackEmail(
                    errorMessage: '$title ($message)',
                    stackTrace: stack,
                  ),
                  icon: Icon(Icons.feedback_outlined),
                  label: Text('Hibajelentés'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum LErrorType { error, warning, info }
