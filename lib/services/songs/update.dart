import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../bank/update.dart';
import '../http/dio_provider.dart';
import '../task/task_queue.dart';
import 'bank_song_update_task.dart';

final bankSongUpdateSchedulerProvider =
    NotifierProvider<BankSongUpdateScheduler, AsyncValue<void>>(
      BankSongUpdateScheduler.new,
    );

final bankSongUpdateTasksProvider = Provider<List<BankSongUpdateTask>>((ref) {
  final tasks = ref.watch(backgroundTaskQueueProvider).tasks;
  return List.unmodifiable(tasks.whereType<BankSongUpdateTask>());
});

final currentBankSongUpdateTaskProvider = Provider<BankSongUpdateTask?>((ref) {
  final tasks = ref.watch(bankSongUpdateTasksProvider);

  for (final task in tasks) {
    if (task.isRunning) {
      return task;
    }
  }

  if (tasks.isEmpty) return null;
  return tasks.last;
});

final latestFailedBankSongUpdateTaskProvider = Provider<BankSongUpdateTask?>((
  ref,
) {
  final tasks = ref.watch(bankSongUpdateTasksProvider);

  for (var index = tasks.length - 1; index >= 0; index--) {
    final task = tasks[index];
    if (task.isFailed) {
      return task;
    }
  }

  return null;
});

final bankSongUpdateOverallProgressProvider = Provider<double?>((ref) {
  final tasks = ref.watch(bankSongUpdateTasksProvider);
  if (tasks.isEmpty) return null;

  var completedUnits = 0.0;
  for (final task in tasks) {
    if (task.isTerminal) {
      completedUnits += 1;
      continue;
    }

    if (task.isRunning && task.progress != null) {
      completedUnits += task.progress!;
    }
  }

  return completedUnits / tasks.length;
});

final allBankSongUpdateTasksSettledProvider = Provider<bool>((ref) {
  final schedulerState = ref.watch(bankSongUpdateSchedulerProvider);
  if (schedulerState.isLoading || schedulerState.hasError) {
    return false;
  }

  final tasks = ref.watch(bankSongUpdateTasksProvider);
  return tasks.every((task) => task.isTerminal);
});

class BankSongUpdateScheduler extends Notifier<AsyncValue<void>> {
  bool _isScheduling = false;

  @override
  AsyncValue<void> build() {
    return const AsyncValue.data(null);
  }

  Future<void> refreshAllEnabledBanks() async {
    if (_isScheduling) return;

    _isScheduling = true;
    state = const AsyncValue.loading();

    try {
      final dio = ref.read(dioProvider);
      await updateBanks(dio);

      final enabledBanks = await (db.select(
        db.banks,
      )..where((bank) => bank.isEnabled)).get();

      final queue = ref.read(backgroundTaskQueueProvider.notifier);
      await queue.removeFinishedTasks();
      queue.enqueueAll(
        enabledBanks.map((bank) => BankSongUpdateTask(bank: bank, dio: dio)),
      );

      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    } finally {
      _isScheduling = false;
    }
  }
}
