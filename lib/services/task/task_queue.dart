import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/log/logger.dart';
import 'background_task.dart';

final backgroundTaskQueueProvider =
    NotifierProvider<BackgroundTaskQueue, BackgroundTaskQueueState>(
      BackgroundTaskQueue.new,
    );

final currentBackgroundTaskProvider = Provider<BackgroundTask?>((ref) {
  return ref.watch(backgroundTaskQueueProvider).currentTask;
});

class BackgroundTaskQueueState {
  const BackgroundTaskQueueState({
    this.tasks = const [],
    this.isProcessing = false,
  });

  final List<BackgroundTask> tasks;
  final bool isProcessing;

  BackgroundTask? get currentTask {
    for (final task in tasks) {
      if (task.isRunning) {
        return task;
      }
    }
    return null;
  }

  List<BackgroundTask> get pendingTasks {
    return List.unmodifiable(tasks.where((task) => task.isPending));
  }

  List<BackgroundTask> get completedTasks {
    return List.unmodifiable(tasks.where((task) => task.isCompleted));
  }

  List<BackgroundTask> get failedTasks {
    return List.unmodifiable(tasks.where((task) => task.isFailed));
  }

  bool get hasQueuedWork {
    return tasks.any((task) => !task.isTerminal);
  }

  BackgroundTaskQueueState copyWith({
    List<BackgroundTask>? tasks,
    bool? isProcessing,
  }) {
    return BackgroundTaskQueueState(
      tasks: tasks ?? this.tasks,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}

class BackgroundTaskQueue extends Notifier<BackgroundTaskQueueState> {
  final Map<BackgroundTask, StreamSubscription<void>> _taskSubscriptions = {};
  bool _isProcessing = false;

  @override
  BackgroundTaskQueueState build() {
    ref.onDispose(() {
      final subscriptions = List<StreamSubscription<void>>.of(
        _taskSubscriptions.values,
      );
      final trackedTasks = List<BackgroundTask>.of(_taskSubscriptions.keys);
      _taskSubscriptions.clear();

      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }

      for (final task in trackedTasks) {
        unawaited(task.dispose());
      }
    });

    return const BackgroundTaskQueueState();
  }

  void enqueue(BackgroundTask task) {
    if (_hasQueuedEquivalent(task)) {
      unawaited(task.dispose());
      return;
    }

    _attachTask(task);
    state = state.copyWith(tasks: List.unmodifiable([...state.tasks, task]));
    unawaited(_processQueue());
  }

  void enqueueAll(Iterable<BackgroundTask> tasks) {
    final acceptedTasks = <BackgroundTask>[];
    final blockedKeys = state.tasks
        .where((task) => !task.isTerminal)
        .map((task) => task.deduplicationKey)
        .toSet();

    for (final task in tasks) {
      if (blockedKeys.contains(task.deduplicationKey)) {
        unawaited(task.dispose());
        continue;
      }

      blockedKeys.add(task.deduplicationKey);
      _attachTask(task);
      acceptedTasks.add(task);
    }

    if (acceptedTasks.isEmpty) return;

    state = state.copyWith(
      tasks: List.unmodifiable([...state.tasks, ...acceptedTasks]),
    );
    unawaited(_processQueue());
  }

  Future<void> removeFinishedTasks() async {
    final remainingTasks = <BackgroundTask>[];

    for (final task in state.tasks) {
      if (task.isTerminal) {
        await _detachTask(task);
        await task.dispose();
        continue;
      }

      remainingTasks.add(task);
    }

    state = state.copyWith(tasks: List.unmodifiable(remainingTasks));
  }

  void retryFailedTasks() {
    var retriedAnyTask = false;

    for (final task in state.tasks) {
      if (!task.isFailed) continue;

      task.requeue();
      retriedAnyTask = true;
    }

    if (!retriedAnyTask) return;

    _publishState();
    unawaited(_processQueue());
  }

  bool _hasQueuedEquivalent(BackgroundTask task) {
    return state.tasks.any(
      (existingTask) =>
          !existingTask.isTerminal &&
          existingTask.deduplicationKey == task.deduplicationKey,
    );
  }

  void _attachTask(BackgroundTask task) {
    _taskSubscriptions[task] = task.updates.listen((_) {
      _publishState();
    });
  }

  Future<void> _detachTask(BackgroundTask task) async {
    final subscription = _taskSubscriptions.remove(task);
    await subscription?.cancel();
  }

  void _publishState() {
    state = state.copyWith(
      tasks: List.unmodifiable([...state.tasks]),
      isProcessing: _isProcessing,
    );
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;

    _isProcessing = true;
    _publishState();

    try {
      while (true) {
        final nextTask = _firstPendingTask();
        if (nextTask == null) break;

        try {
          await nextTask.run();
        } catch (error, stackTrace) {
          log.warning(
            'Background task failed: ${nextTask.title}',
            error,
            stackTrace,
          );
        } finally {
          _publishState();
        }
      }
    } finally {
      _isProcessing = false;
      _publishState();
    }
  }

  BackgroundTask? _firstPendingTask() {
    for (final task in state.tasks) {
      if (task.isPending) {
        return task;
      }
    }

    return null;
  }
}
