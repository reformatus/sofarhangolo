import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/config.dart';
import '../../../data/log/level_style.dart';
import '../../../data/log/provider.dart';
import '../centered_hint.dart';

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
            title: Text('Napló'),
            automaticallyImplyLeading: false,
            actions: [
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

class LogMessageCard extends ConsumerWidget {
  final LogMessage message;

  const LogMessageCard({super.key, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = message.record;
    final level = record.level;
    final color = colorForLogLevel(level);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Badge(
        isLabelVisible: !message.isRead,
        backgroundColor: color,
        padding: EdgeInsets.all(3),
        child: Card(
          elevation: message.isRead ? 1 : 4,
          color: Color.lerp(
            color,
            Theme.of(context).scaffoldBackgroundColor,
            0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(
                  iconForLogLevel(level),
                  color: color.withAlpha(200),
                ),
                title: Text(
                  record.message,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  '${record.time.hour}:${record.time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: !message.isRead
                    ? IconButton(
                        icon: Icon(Icons.check),
                        tooltip: 'Olvasottnak jelölés',
                        onPressed: () {
                          ref
                              .read(logMessagesProvider.notifier)
                              .markAsRead(message);
                        },
                      )
                    : null,
              ),
              if (record.error != null || record.stackTrace != null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (record.error != null) Text(record.error.toString()),
                      if (record.stackTrace != null)
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: 100),
                          child: SingleChildScrollView(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                record.stackTrace.toString(),
                                style: TextStyle(fontFamily: 'Courier New'),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
