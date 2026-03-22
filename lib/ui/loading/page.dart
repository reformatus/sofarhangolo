import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../services/error/app_error.dart';
import '../../services/bank/bank_updated.dart';
import '../../services/preferences/preferences_parent.dart';
import '../../services/songs/update.dart';
import '../common/error/card.dart';
import 'banner.dart';

class LoadingPage extends ConsumerStatefulWidget {
  const LoadingPage({super.key});

  @override
  ConsumerState<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends ConsumerState<LoadingPage> {
  bool _hasNavigated = false;
  late final Future preferenceLoader = loadAllPreferences(ref);

  void _checkAndNavigateIfReady() async {
    if (_hasNavigated) return;

    final hasEverUpdated = ref.read(hasEverUpdatedAnythingProvider);
    final bankStates = ref.read(updateAllBanksSongsProvider);

    if (hasEverUpdated.value == true ||
        (bankStates.hasValue && bankStates.value!.values.every(isDone))) {
      _hasNavigated = true;

      await preferenceLoader;

      // settings should have loaded

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.replace('/home');
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();

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

    // Listen for bank states and navigate when done
    ref.listenManual(updateAllBanksSongsProvider, (previous, next) {
      _checkAndNavigateIfReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasEverUpdatedProvider = ref.watch(hasEverUpdatedAnythingProvider);
    final bankStates = ref.watch(updateAllBanksSongsProvider);

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
                  child: LErrorCard(
                    type: LErrorType.error,
                    title: 'Hiba a beállítások betöltése közben',
                    message: snapshot.error.toString(),
                    stack: snapshot.stackTrace?.toString() ?? '',
                    icon: Icons.settings,
                  ),
                ),
              ),
            );
          }

          // Continue with normal UI flow
          return Center(
            child: hasEverUpdatedProvider.value == false
                ? switch (bankStates) {
                    AsyncError(:final error, :final stackTrace) => () {
                      final appError = AppError.from(
                        error,
                        stackTrace: stackTrace,
                      );

                      if (appError.category == AppErrorCategory.frontend) {
                        return LErrorCard(
                          type: LErrorType.error,
                          title: 'Hiba a tárak frissítése közben',
                          message: error.toString(),
                          stack: stackTrace.toString(),
                          icon: Icons.error,
                          onRetry: () =>
                              ref.invalidate(updateAllBanksSongsProvider),
                        );
                      }

                      return LErrorCard.fromAppError(
                        error: appError,
                        onRetry: () =>
                            ref.invalidate(updateAllBanksSongsProvider),
                      );
                    }(),
                    AsyncValue(:final value) =>
                      value == null
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
                                            value: () {
                                              if (!bankStates.hasValue) {
                                                return null;
                                              }
                                              int stateCount = value.length;
                                              if (stateCount == 0) return null;

                                              int doneCount = value.values
                                                  .where(
                                                    (e) =>
                                                        e != null &&
                                                        (e.toUpdateCount ==
                                                            e.updatedCount),
                                                  )
                                                  .length;

                                              return doneCount / stateCount;
                                            }(),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (bankStates.hasValue)
                                      ...value.entries.map(
                                        (e) => Padding(
                                          padding: EdgeInsets.only(left: 20),
                                          child: ListTile(
                                            leading: isDone(e.value)
                                                ? Icon(Icons.check)
                                                : SizedBox.square(
                                                    dimension: 25,
                                                    child:
                                                        CircularProgressIndicator(
                                                          value: getProgress(
                                                            e.value,
                                                          ),
                                                        ),
                                                  ),
                                            title: Text(
                                              e.key.name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            subtitle: Text(
                                              e.value != null
                                                  ? "${e.value!.updatedCount} / ${e.value!.toUpdateCount} frissítve"
                                                  : "",
                                            ),
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
