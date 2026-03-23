import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../main.dart';
import '../../services/ui/messenger_service.dart';
import '../../ui/common/log/dialog.dart';

part 'provider.g.dart';

@Riverpod(keepAlive: true)
class ShowLogLevel extends _$ShowLogLevel {
  @override
  Level build() {
    return Level.WARNING;
  }
}

@Riverpod(keepAlive: true)
class LogMessages extends _$LogMessages {
  int _warningSnackBarSerial = 0;

  Color _snackBarColorForLevel(Level level) {
    if (level.value >= Level.SEVERE.value) {
      return Colors.red;
    }
    if (level.value >= Level.WARNING.value) {
      return Colors.orange;
    }
    return Colors.blue;
  }

  @override
  List<LogMessage> build() {
    return [];
  }

  void addRecord(LogRecord record) {
    state.add(LogMessage(record));
    if (record.level.value >= Level.WARNING.value) {
      final messenger = ref.read(messengerServiceProviderProvider);
      _warningSnackBarSerial++;
      final thisSnackBarSerial = _warningSnackBarSerial;
      messenger.state?.removeCurrentSnackBar(
        reason: SnackBarClosedReason.remove,
      );
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Bezárás',
                onPressed: () {
                  messenger.state?.hideCurrentSnackBar();
                },
              ),
              Expanded(child: Text(record.message)),
            ],
          ),
          backgroundColor: _snackBarColorForLevel(record.level),
          action: SnackBarAction(
            label: 'Napló',
            onPressed: () {
              final context = appNavigatorKey.currentContext;
              if (context == null) {
                return;
              }
              showDialog<void>(
                context: context,
                builder: (_) => const LogViewDialog(),
              );
            },
          ),
        ),
      );

      Future<void>.delayed(const Duration(seconds: 6), () {
        if (thisSnackBarSerial != _warningSnackBarSerial) {
          return;
        }
        messenger.state?.hideCurrentSnackBar(
          reason: SnackBarClosedReason.timeout,
        );
      });
    }
    ref.notifyListeners();
  }

  void markAllRead() {
    for (var e in state) {
      e.isRead = true;
    }
    ref.notifyListeners();
  }

  void markAsRead(LogMessage message) {
    if (!message.isRead) {
      message.isRead = true;
      ref.notifyListeners();
    }
  }
}

@riverpod
int unreadLogCount(Ref ref) {
  final logs = ref.watch(logMessagesProvider);
  final level = ref.watch(showLogLevelProvider);
  return logs
      .where((e) => e.record.level.value >= level.value && !e.isRead)
      .length;
}

class LogMessage {
  LogRecord record;
  bool isRead = false;

  LogMessage(this.record);
  LogMessage.read(this.record) : isRead = true;
}
