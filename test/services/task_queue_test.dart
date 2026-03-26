import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofar/services/task/background_task.dart';
import 'package:sofar/services/task/task_queue.dart';

class _FakeTask extends BackgroundTask {
  _FakeTask({
    required this.taskTitle,
    this.onExecute,
    this.failuresBeforeSuccess = 0,
  });

  final String taskTitle;
  final Future<void> Function()? onExecute;
  final int failuresBeforeSuccess;

  int _attempts = 0;

  int get attempts => _attempts;

  @override
  String get title => taskTitle;

  @override
  String get subtitle => taskTitle;

  @override
  double? get progress => isCompleted ? 1 : 0;

  @override
  int get totalCount => 1;

  @override
  int get doneCount => isCompleted ? 1 : 0;

  @override
  int get errorCount => isFailed ? 1 : 0;

  @override
  Future<void> execute() async {
    _attempts++;
    await onExecute?.call();

    if (_attempts <= failuresBeforeSuccess) {
      throw StateError('planned failure');
    }
  }
}

void main() {
  group('BackgroundTaskQueue', () {
    test('runs queued tasks sequentially', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final firstTaskCompleter = Completer<void>();
      final secondTaskCompleter = Completer<void>();
      final startedTasks = <String>[];

      final firstTask = _FakeTask(
        taskTitle: 'first',
        onExecute: () async {
          startedTasks.add('first');
          await firstTaskCompleter.future;
        },
      );
      final secondTask = _FakeTask(
        taskTitle: 'second',
        onExecute: () async {
          startedTasks.add('second');
          secondTaskCompleter.complete();
        },
      );

      container.read(backgroundTaskQueueProvider.notifier).enqueueAll([
        firstTask,
        secondTask,
      ]);

      await Future<void>.delayed(Duration.zero);
      expect(startedTasks, ['first']);
      expect(container.read(backgroundTaskQueueProvider).isProcessing, isTrue);

      firstTaskCompleter.complete();
      await secondTaskCompleter.future;
      await Future<void>.delayed(Duration.zero);

      expect(startedTasks, ['first', 'second']);

      final queueState = container.read(backgroundTaskQueueProvider);
      expect(queueState.tasks.every((task) => task.isCompleted), isTrue);
      expect(queueState.isProcessing, isFalse);
    });

    test('retries failed tasks without re-enqueueing them', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final task = _FakeTask(taskTitle: 'flaky', failuresBeforeSuccess: 1);

      container.read(backgroundTaskQueueProvider.notifier).enqueue(task);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(task.isFailed, isTrue);
      expect(task.attempts, 1);

      container.read(backgroundTaskQueueProvider.notifier).retryFailedTasks();

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(task.isCompleted, isTrue);
      expect(task.attempts, 2);
      expect(container.read(backgroundTaskQueueProvider).tasks, hasLength(1));
    });
  });
}
