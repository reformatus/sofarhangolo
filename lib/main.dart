import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'services/app_links/app_links.dart';
import 'services/app_links/navigation.dart';
import 'services/app_links/web_initial_app_uri.dart';
import 'services/preferences/providers/general.dart';
import 'ui/cue/cue_page_type.dart';

import 'config/config.dart';
import 'data/database.dart';
import 'data/log/logger.dart';
import 'services/ui/messenger_service.dart';
import 'ui/base/cues/page.dart';
import 'ui/base/home/page.dart';
import 'ui/base/scaffold.dart';
import 'ui/base/songs/page.dart';
import 'ui/cue/loader.dart';
import 'ui/loading/launch_page.dart';
import 'ui/loading/page.dart';
import 'ui/song/page.dart';

part 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoRouter.optionURLReflectsImperativeAPIs = true;
  if (kIsWeb) {
    usePathUrlStrategy();
  } else {
    await FullScreen.ensureInitialized();
  }
  db = LyricDatabase();
  final initialAppUri = kIsWeb
      ? captureInitialWebAppUri(config: appConfig)
      : await captureInitialAppUri();

  runApp(
    ProviderScope(
      // Disable Riverpod's built-in retry; Dio's RetryInterceptor handles network retries.
      retry: (_, _) => null,
      child: LyricApp(initialAppUri: initialAppUri),
    ),
  );
}

class LyricApp extends ConsumerStatefulWidget {
  const LyricApp({required this.initialAppUri, super.key});

  final Uri? initialAppUri;

  @override
  ConsumerState<LyricApp> createState() => _LyricAppState();
}

class _LyricAppState extends ConsumerState<LyricApp> {
  GoRouter? _router;

  @override
  void initState() {
    initLogger(ref);
    super.initState();
  }

  void _finishStartup() {
    if (_router != null) return;

    final startupRoute = widget.initialAppUri == null
        ? null
        : initialRouteFromAppUri(widget.initialAppUri);
    final router = createAppRouter(initialLocation: startupRoute);

    setState(() {
      _router = router;
    });

    if (kIsWeb && startupRoute != null && startupRoute != '/home') {
      _scheduleWebStartupRouteReconciliation(
        router: router,
        startupRoute: startupRoute,
      );
    }
  }

  void _scheduleWebStartupRouteReconciliation({
    required GoRouter router,
    required String startupRoute,
  }) {
    void reconcile() {
      if (!mounted || _router != router) return;

      final currentRoute = router.routeInformationProvider.value.uri.toString();
      if (currentRoute != startupRoute) {
        router.go(startupRoute);
        return;
      }

      syncWebBrowserUrlToAppRoute(startupRoute, config: appConfig);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      reconcile();
      Future<void>.delayed(const Duration(milliseconds: 300), reconcile);
    });
  }

  @override
  Widget build(BuildContext context) {
    final generalPrefs = ref.watch(generalPreferencesProvider);

    final theme = ThemeData.from(
      colorScheme: ColorScheme.fromSeed(
        seedColor: appConfig.colors.seedColor,
        primary: appConfig.colors.primaryColor,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );
    final darkTheme = ThemeData.from(
      colorScheme: ColorScheme.fromSeed(
        seedColor: appConfig.colors.seedColor,
        primary: appConfig.colors.primaryColor,
        surface: generalPrefs.oledBlackBackground ? Colors.black : null,
        brightness: Brightness.dark,
      ),
    );

    final commonArgs = (
      themeMode: generalPrefs.appBrightness,
      darkTheme: darkTheme,
      theme: theme,
      scaffoldMessengerKey: messengerService.scaffoldMessengerKey,
      supportedLocales: const [Locale('hu')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
    );

    if (_router == null) {
      return MaterialApp(
        themeMode: commonArgs.themeMode,
        darkTheme: commonArgs.darkTheme,
        theme: commonArgs.theme,
        scaffoldMessengerKey: commonArgs.scaffoldMessengerKey,
        supportedLocales: commonArgs.supportedLocales,
        localizationsDelegates: commonArgs.localizationsDelegates,
        debugShowCheckedModeBanner: commonArgs.debugShowCheckedModeBanner,
        home: LoadingPage(onReady: _finishStartup),
      );
    }

    return MaterialApp.router(
      themeMode: generalPrefs.appBrightness,
      darkTheme: darkTheme,
      theme: theme,
      scaffoldMessengerKey: messengerService.scaffoldMessengerKey,
      routerConfig: _router!,
      supportedLocales: const [Locale('hu')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}
