import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'package:go_router/go_router.dart';
import 'services/preferences/providers/general.dart';
import 'ui/cue/cue_page_type.dart';
import 'package:path_provider/path_provider.dart';

import 'config/config.dart';
import 'data/database.dart';
import 'data/log/logger.dart';
import 'services/ui/messenger_service.dart';
import 'ui/base/cues/page.dart';
import 'ui/base/home/page.dart';
import 'ui/base/scaffold.dart';
import 'ui/base/songs/page.dart';
import 'ui/cue/loader.dart';
import 'ui/loading/page.dart';
import 'ui/song/page.dart';

part 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FullScreen.ensureInitialized();
  dataDir = await getApplicationDocumentsDirectory();
  db = LyricDatabase();

  runApp(
    ProviderScope(
      // Disable Riverpod's built-in retry; Dio's RetryInterceptor handles network retries.
      retry: (_, _) => null,
      child: const LyricApp(),
    ),
  );
}

class LyricApp extends ConsumerStatefulWidget {
  const LyricApp({super.key});

  @override
  ConsumerState<LyricApp> createState() => _LyricAppState();
}

class _LyricAppState extends ConsumerState<LyricApp> {
  @override
  void initState() {
    initLogger(ref);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final generalPrefs = ref.watch(generalPreferencesProvider);

    return MaterialApp.router(
      themeMode: generalPrefs.appBrightness,
      darkTheme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(
          seedColor: appConfig.colors.seedColor,
          primary: appConfig.colors.primaryColor,
          surface: generalPrefs.oledBlackBackground ? Colors.black : null,
          brightness: Brightness.dark,
        ),
      ),
      theme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(
          seedColor: appConfig.colors.seedColor,
          primary: appConfig.colors.primaryColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      scaffoldMessengerKey: messengerService.scaffoldMessengerKey,
      routerConfig: appRouter,
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
