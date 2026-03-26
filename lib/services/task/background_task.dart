import 'dart:async';

import 'package:flutter/foundation.dart';

enum BackgroundTaskStatus { pending, running, completed, failed }

abstract class BackgroundTask {
  BackgroundTask();

  final StreamController<void> _updates = StreamController.broadcast();

  BackgroundTaskStatus _status = BackgroundTaskStatus.pending;
  Object? _lastError;
  StackTrace? _lastErrorStackTrace;

  String get deduplicationKey => '${runtimeType}:${identityHashCode(this)}';

  String get title;
  String get subtitle;
  double? get progress;
  int get totalCount;
  int get doneCount;
  int get errorCount;

  BackgroundTaskStatus get status => _status;
  Object? get lastError => _lastError;
  StackTrace? get lastErrorStackTrace => _lastErrorStackTrace;
  Stream<void> get updates => _updates.stream;

  bool get isPending => _status == BackgroundTaskStatus.pending;
  bool get isRunning => _status == BackgroundTaskStatus.running;
  bool get isCompleted => _status == BackgroundTaskStatus.completed;
  bool get isFailed => _status == BackgroundTaskStatus.failed;
  bool get isTerminal => isCompleted || isFailed;

  @nonVirtual
  Future<void> run() async {
    _lastError = null;
    _lastErrorStackTrace = null;
    resetProgress();
    _status = BackgroundTaskStatus.running;
    notifyListeners();

    try {
      await execute();
      _status = BackgroundTaskStatus.completed;
      notifyListeners();
    } catch (error, stackTrace) {
      _lastError = error;
      _lastErrorStackTrace = stackTrace;
      _status = BackgroundTaskStatus.failed;
      notifyListeners();
      rethrow;
    }
  }

  void requeue() {
    _lastError = null;
    _lastErrorStackTrace = null;
    _status = BackgroundTaskStatus.pending;
    notifyListeners();
  }

  @protected
  @mustCallSuper
  void resetProgress() {}

  @protected
  Future<void> execute();

  @protected
  void notifyListeners() {
    if (!_updates.isClosed) {
      _updates.add(null);
    }
  }

  @mustCallSuper
  Future<void> dispose() async {
    await _updates.close();
  }
}
