import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_links/navigation.dart';
import '../../services/bank/bank_updated.dart';
import '../../services/error/app_error.dart';
import '../../services/preferences/preferences_parent.dart';
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

    ref.listenManual(hasEverUpdatedAnythingProvider, (previous, next) {
      _checkAndNavigateIfReady();
      next.whenData((didUpdateAnything) async {
        if (didUpdateAnything) {
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

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: FutureBuilder(
        future: preferenceLoader,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
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
                    _ => const _LoadingIndicator(),
                  }
                : const _LoadingIndicator(),
          );
        },
      ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/icon/sofar_dalapp_rounded_512.png',
          width: 104,
          height: 104,
        ),
        const SizedBox(height: 24),
        const SizedBox.square(
          dimension: 32,
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }
}
