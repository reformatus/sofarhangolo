import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../config/config.dart';
import '../../../data/log/level_style.dart';
import '../../../data/log/provider.dart';
import '../../../services/text_export/diagnostics.dart';
import '../../../services/ui/messenger_service.dart';
import '../centered_hint.dart';
import '../error/card.dart';

class LogViewDialog extends ConsumerStatefulWidget {
  const LogViewDialog({super.key});

  @override
  ConsumerState<LogViewDialog> createState() => _LogViewDialogState();
}

class _LogViewDialogState extends ConsumerState<LogViewDialog> {
  late final ScrollController scrollController;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(logMessagesProvider);
    // Needs to take all types into account, so not using the existing provider
    final unreadCount = messages.where((e) => !e.isRead).length;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: appConfig.breakpoints.tabletFromWidth,
        ),
        child: Scaffold(
          appBar: AppBar(
            title: SelectableText('Napló'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                onPressed: () => messengerService.copyToClipboard(
                  messages
                      .map(
                        (m) => formatLogEntry(
                          level: m.record.level.name,
                          time: m.record.time,
                          message: m.record.message,
                          error: m.record.error,
                          stackTrace: m.record.stackTrace,
                        ),
                      )
                      .join('\n\n'),
                ),
                icon: Icon(Icons.copy_all),
                tooltip: 'Összes másolása',
              ),
              IconButton(onPressed: context.pop, icon: Icon(Icons.close)),
            ],
            actionsPadding: EdgeInsets.only(right: 8),
          ),
          body: messages.isEmpty
              ? Center(
                  child: CenteredHint(
                    'Nincs naplóüzenet',
                    iconData: Icons.mark_chat_read_outlined,
                  ),
                )
              : Padding(
                  padding: EdgeInsets.only(
                    top: 4,
                    bottom: unreadCount > 0 ? 65 : 4,
                  ),
                  child: FadingEdgeScrollView.fromScrollView(
                    child: ListView.builder(
                      controller: scrollController,
                      shrinkWrap: true,
                      reverse: true,
                      itemBuilder: (context, i) => LogMessageCard(
                        message: messages[messages.length - 1 - i],
                      ),
                      itemCount: messages.length,
                    ),
                  ),
                ),
          floatingActionButton: unreadCount > 0
              ? FloatingActionButton.small(
                  onPressed: () =>
                      ref.read(logMessagesProvider.notifier).markAllRead(),
                  tooltip: 'Összes olvasottnak jelölése',
                  child: Icon(Icons.done_all),
                )
              : null,
        ),
      ),
    );
  }
}

class LogMessageCard extends StatelessWidget {
  final LogMessage message;

  const LogMessageCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final record = message.record;
    final error = record.error;

    // The log message is the card's title; an attached error contributes
    // the body/failure/stack fields and the action buttons. Without an
    // error the message still gets a card, styled by log level.
    final card = error != null
        ? LErrorCard.fromError(
            error: error,
            stackTrace: record.stackTrace,
            title: record.message,
            icon: iconForLogLevel(record.level),
          )
        : LErrorCard(
            type: _typeForLogLevel(record.level),
            title: record.message,
            icon: iconForLogLevel(record.level),
            showReportButton: false,
          );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!message.isRead)
                  Container(
                    key: const ValueKey('log-unread-dot'),
                    width: 8,
                    height: 8,
                    margin: EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: colorForLogLevel(record.level),
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(_formatTime(record.time), style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          card,
        ],
      ),
    );
  }
}

LErrorType _typeForLogLevel(Level level) {
  if (level.value >= Level.SEVERE.value) return LErrorType.error;
  if (level.value >= Level.WARNING.value) return LErrorType.warning;
  return LErrorType.info;
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}
