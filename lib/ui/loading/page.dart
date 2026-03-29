import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/config.dart';
import '../../services/app_links/navigation.dart';
import '../../services/error/app_error.dart';
import '../../services/bank/bank_updated.dart';
import '../../services/preferences/preferences_parent.dart';
import '../../services/songs/bank_song_update_task.dart';
import '../../services/songs/update.dart';
import '../../services/task/task_queue.dart';
import '../common/error/card.dart';
import 'banner.dart';

class LoadingPage extends ConsumerStatefulWidget {
  const LoadingPage({
    required this.initialAppUri,
    required this.onReady,
    super.key,
  });

  final Uri? initialAppUri;
  final ValueChanged<String> onReady;

  @override
  ConsumerState<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends ConsumerState<LoadingPage> {
  bool _hasNavigated = false;
  bool _hasRequestedInitialRefresh = false;
  late final Future preferenceLoader = loadAllPreferences(ref);

  void _requestInitialRefresh() {
    if (_hasRequestedInitialRefresh) return;

    _hasRequestedInitialRefresh = true;
    unawaited(
      ref
          .read(bankSongUpdateSchedulerProvider.notifier)
          .refreshAllEnabledBanks(),
    );
  }

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

  void _checkAndNavigateIfReady() async {
    if (_hasNavigated) return;

    final hasEverUpdated = ref.read(hasEverUpdatedAnythingProvider);
    if (!hasEverUpdated.hasValue) return;

    if (hasEverUpdated.value == true) {
      await _finishStartup();
      return;
    }

    if (!_hasRequestedInitialRefresh) return;

    final schedulerState = ref.read(bankSongUpdateSchedulerProvider);
    final allTasksSettled = ref.read(allBankSongUpdateTasksSettledProvider);

    if (schedulerState.hasValue && allTasksSettled) {
      await _finishStartup();
    }
  }

  Future<void> _finishStartup() async {
    if (_hasNavigated) return;

    _hasNavigated = true;
    await preferenceLoader;

    if (!mounted) return;

    widget.onReady(initialRouteFromAppUri(widget.initialAppUri));
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestInitialRefresh();
    });

    // Listen for hasEverUpdated changes and show banner
    ref.listenManual(hasEverUpdatedAnythingProvider, (previous, next) {
      _checkAndNavigateIfReady();
      next.whenData((d) async {
        if (d) {
          Future(() {
            showOnlineBanksUpdatingBanner();
          });
        }
      });
    });

    ref.listenManual(bankSongUpdateSchedulerProvider, (previous, next) {
      _checkAndNavigateIfReady();
    });

    ref.listenManual(backgroundTaskQueueProvider, (previous, next) {
      _checkAndNavigateIfReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasEverUpdatedProvider = ref.watch(hasEverUpdatedAnythingProvider);
    final schedulerState = ref.watch(bankSongUpdateSchedulerProvider);
    final bankTasks = ref.watch(bankSongUpdateTasksProvider);
    final overallProgress = ref.watch(bankSongUpdateOverallProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.appName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(),
        ),
      ),
      body: FutureBuilder(
        future: preferenceLoader,
        builder: (context, snapshot) {
          // Show error if preferences failed to load
          if (snapshot.hasError) {
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LErrorCard.fromError(
                    error: snapshot.error!,
                    stackTrace: snapshot.stackTrace,
                    title: 'Hiba a beállítások betöltése közben',
                    icon: Icons.settings,
                  ),
                ),
              ),
            );
          }

          // Continue with normal UI flow
          return Center(
            child: hasEverUpdatedProvider.value == false
                ? switch (schedulerState) {
                    AsyncError(:final error, :final stackTrace)
                        when bankTasks.isEmpty =>
                      () {
                        final appError = AppError.from(
                          error,
                          stackTrace: stackTrace,
                        );

                        return LErrorCard.fromAppError(
                          error: appError,
                          title: 'Hiba a tárak frissítése közben',
                          icon: Icons.cloud_sync_outlined,
                          onRetry: () {
                            _hasRequestedInitialRefresh = false;
                            _requestInitialRefresh();
                          },
                        );
                      }(),
                    _ =>
                      schedulerState.isLoading && bankTasks.isEmpty
                          ? Center(child: CircularProgressIndicator())
                          : ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: 600),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Card(
                                      margin: EdgeInsets.only(bottom: 15),
                                      clipBehavior: Clip.antiAlias,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Padding(
                                            padding: EdgeInsets.only(
                                              top: 16,
                                              left: 16,
                                              bottom: 13,
                                            ),
                                            child: Text(
                                              'Online tárak frissítése...',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleLarge,
                                            ),
                                          ),
                                          LinearProgressIndicator(
                                            value: overallProgress,
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...bankTasks.map(
                                      (task) => Padding(
                                        padding: EdgeInsets.only(left: 20),
                                        child: ListTile(
                                          leading: SizedBox.square(
                                            dimension: 32,
                                            child: task.logo != null
                                                ? Image.memory(task.logo!)
                                                : Icon(Icons.library_music),
                                          ),
                                          title: Text(
                                            task.title,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          subtitle: Text(task.subtitle),
                                          trailing: _buildTaskStatus(task),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                  }
                : SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
