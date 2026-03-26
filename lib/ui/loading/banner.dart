import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/error/app_error.dart';
import '../../services/connectivity/provider.dart';
import '../../services/songs/bank_song_update_task.dart';
import '../../services/songs/update.dart';
import '../../services/task/task_queue.dart';
import '../../services/ui/messenger_service.dart';
import '../common/error/card.dart';

void showOnlineBanksUpdatingBanner() {
  messengerService.clearBanners();
  messengerService.showBanner(
    MaterialBanner(
      content: UpdatingBanner(),
      padding: EdgeInsets.zero,
      actions: [
        IconButton(
          onPressed: () => messengerService.hideCurrentBanner(),
          icon: Icon(Icons.keyboard_arrow_up),
        ),
      ],
    ),
  );
}

// far future todo: show banks in scrollview, animate scroll to current, use fadingEdgeScrollView
class UpdatingBanner extends ConsumerWidget {
  const UpdatingBanner({super.key});

  Widget _buildTaskStatus(BankSongUpdateTask task) {
    if (task.isCompleted) {
      return Icon(Icons.check);
    }
    if (task.isFailed) {
      return Icon(Icons.error_outline);
    }
    if (task.isRunning) {
      return SizedBox.square(
        dimension: 25,
        child: CircularProgressIndicator(value: task.progress),
      );
    }
    return Icon(Icons.schedule);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionProvider);
    final schedulerState = ref.watch(bankSongUpdateSchedulerProvider);
    final queueState = ref.watch(backgroundTaskQueueProvider);
    final bankTasks = ref.watch(bankSongUpdateTasksProvider);
    final currentTask = ref.watch(currentBankSongUpdateTaskProvider);
    final latestFailedTask = ref.watch(latestFailedBankSongUpdateTaskProvider);
    final overallProgress = ref.watch(bankSongUpdateOverallProgressProvider);

    if (connection == ConnectionType.offline) {
      Future.delayed(
        Duration(seconds: 8),
      ).then((_) => messengerService.hideCurrentBanner());
      return LErrorCard(
        type: LErrorType.warning,
        title: 'Offline vagy.',
        message:
            'A már letöltött kottáidat és az összes dalszöveget továbbra is eléred.',
        icon: Icons.public_off_outlined,
        showReportButton: false,
      );
    }

    if (!schedulerState.isLoading &&
        bankTasks.isNotEmpty &&
        bankTasks.every((task) => task.isTerminal)) {
      Future.delayed(
        Duration(seconds: 3),
      ).then((_) => messengerService.hideCurrentBanner());
    }

    if (schedulerState.hasError && bankTasks.isEmpty) {
      final schedulerError =
          schedulerState.error ?? StateError('Ismeretlen frissítési hiba');
      final appError = AppError.from(
        schedulerError,
        stackTrace: schedulerState.stackTrace,
      );

      if (appError.category == AppErrorCategory.frontend) {
        return LErrorCard(
          key: const ValueKey('scheduler-error'),
          type: LErrorType.error,
          title: 'Hiba a tárak frissítése közben',
          message: schedulerError.toString(),
          stack: schedulerState.stackTrace.toString(),
          icon: Icons.error,
          onRetry: () {
            ref
                .read(bankSongUpdateSchedulerProvider.notifier)
                .refreshAllEnabledBanks();
            showOnlineBanksUpdatingBanner();
          },
        );
      }

      return LErrorCard.fromAppError(
        key: const ValueKey('scheduler-error'),
        error: appError,
        onRetry: () {
          ref
              .read(bankSongUpdateSchedulerProvider.notifier)
              .refreshAllEnabledBanks();
          showOnlineBanksUpdatingBanner();
        },
      );
    }

    if (!queueState.isProcessing && latestFailedTask != null) {
      final taskError =
          latestFailedTask.lastError ?? StateError('Ismeretlen feladathiba');
      final appError = AppError.from(
        taskError,
        stackTrace: latestFailedTask.lastErrorStackTrace,
      );

      return LErrorCard.fromAppError(
        key: const ValueKey('task-error'),
        error: appError,
        onRetry: () {
          ref.read(backgroundTaskQueueProvider.notifier).retryFailedTasks();
          showOnlineBanksUpdatingBanner();
        },
      );
    }

    return AnimatedSwitcher(
      duration: Durations.medium2,
      child: schedulerState.isLoading && currentTask == null
          ? _buildBannerStructure(
              key: const ValueKey('loading'),
              isLoading: true,
            )
          : _buildBannerStructure(
              key: const ValueKey('data'),
              task: currentTask,
              overallProgress: overallProgress,
            ),
    );
  }

  Widget _buildBannerStructure({
    Key? key,
    BankSongUpdateTask? task,
    double? overallProgress,
    bool isLoading = false,
  }) {
    Widget leading;
    Widget? trailing;
    String title = '';
    String message = '';

    if (isLoading) {
      leading = SizedBox.square(
        dimension: 25,
        child: CircularProgressIndicator(),
      );
      title = 'Online tárak frissítése';
      message = 'Frissítendő tárak betöltése...';
    } else {
      leading = SizedBox.square(
        dimension: 28,
        child: task?.tinyLogo != null
            ? Image.memory(task!.tinyLogo!)
            : task?.logo != null
            ? Image.memory(task!.logo!)
            : Icon(Icons.library_music),
      );

      if (task != null) {
        title = task.title;
        message = task.subtitle;
        trailing = _buildTaskStatus(task);
      } else {
        title = 'Online tárak frissítése';
        message = 'Nincs futó frissítés.';
      }
    }

    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: isLoading ? null : overallProgress),
        Padding(
          padding: EdgeInsets.only(left: 10, bottom: 5),
          child: ListTile(
            leading: leading,
            title: Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(message),
            trailing: trailing,
          ),
        ),
      ],
    );
  }
}
