import 'package:flutter/material.dart';

import '../../../config/config.dart';
import '../../../services/error/app_error.dart';
import '../../../services/text_export/diagnostics.dart';
import '../../../services/ui/messenger_service.dart';
import '../../base/home/parts/feedback/send_mail.dart';
import 'code_box.dart';

class LErrorCard extends StatelessWidget {
  const LErrorCard({
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

  factory LErrorCard.fromAppError({
    Key? key,
    required AppError error,
    String? title,
    String? message,
    IconData? icon,
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

  factory LErrorCard.fromError({
    Key? key,
    required Object error,
    StackTrace? stackTrace,
    String? title,
    String? userMessage,
    String? technicalMessage,
    IconData? icon,
    VoidCallback? onRetry,
    String? retryLabel,
    bool? showReportButton,
  }) {
    final appError = AppError.from(
      error,
      stackTrace: stackTrace,
      userMessage: userMessage,
      technicalMessage: technicalMessage,
    );

    return LErrorCard.fromAppError(
      key: key,
      error: appError,
      title: title,
      icon: icon,
      onRetry: onRetry,
      retryLabel: retryLabel,
      showReportButton: showReportButton,
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
    return SelectionArea(
      child: Padding(
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
              if (message != null || errorMessage != null || stack != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      if (message != null) Text(message!),
                      if (errorMessage != null) ErrorCodeBox(errorMessage!),
                      if (stack != null) ErrorCodeBox(stack!),
                    ],
                  ),
                ),
              if (onRetry != null ||
                  errorMessage != null ||
                  stack != null ||
                  showReportButton)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      // The retry action owns the primary slot whenever
                      // it is present.
                      if (onRetry != null)
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: Text(retryLabel ?? 'Újra'),
                        ),
                      ..._secondaryActions(context),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Copy (tertiary) and report (primary, or secondary when [onRetry]
  /// already owns the primary slot), on one row when the screen is wider
  /// than the mobile breakpoint, stacked otherwise.
  List<Widget> _secondaryActions(BuildContext context) {
    final canCopy = errorMessage != null || stack != null;
    if (!canCopy && !showReportButton) return const [];

    Widget reportButton() {
      final icon = Icon(Icons.feedback_outlined);
      final label = Text('Hibajelentés');
      return onRetry == null
          ? FilledButton.icon(onPressed: _report, icon: icon, label: label)
          : FilledButton.tonalIcon(
              onPressed: _report,
              icon: icon,
              label: label,
            );
    }

    final actions = <Widget>[
      if (canCopy)
        TextButton.icon(
          onPressed: () => messengerService.copyToClipboard(
            formatDiagnostics(
              title: title,
              message: message,
              errorMessage: errorMessage,
              stack: stack,
            ),
          ),
          icon: const Icon(Icons.copy),
          label: const Text('Részletek másolása'),
        ),
      if (showReportButton) reportButton(),
    ];

    final isMobile =
        MediaQuery.sizeOf(context).width <
        appConfig.breakpoints.tabletFromWidth;

    if (isMobile) {
      return [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: actions,
        ),
      ];
    }

    return [
      Row(
        spacing: 8,
        children: [for (final action in actions) Expanded(child: action)],
      ),
    ];
  }

  void _report() {
    sendFeedbackEmail(
      errorMessage: [
        title,
        if (message != null) message,
        if (errorMessage != null) errorMessage,
      ].join('\n'),
      stackTrace: stack,
    );
  }
}

enum LErrorType { error, warning, info }
