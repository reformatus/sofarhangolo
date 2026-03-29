import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofar/config/app_config.dart';
import 'package:sofar/services/app_links/web_initial_app_uri_shared.dart';

AppConfig _testConfig({required bool enableRecovery}) {
  return AppConfig(
    appName: 'Test App',
    organisationName: 'Test Org',
    gitHubApiRoot: 'https://api.github.com/repos/test/test',
    domain: 'test.example.com',
    appFeedbackEmail: 'test@example.com',
    homepageRoot: 'https://test.example.com',
    apiRoot: 'https://test.example.com/api',
    webappRoot: 'https://test.example.com/web',
    gitHubRepo: 'https://github.com/test/test/',
    newsRss: 'https://test.example.com/news.rss',
    buttonsRss: 'https://test.example.com/buttons.rss',
    urlScheme: 'testlyric',
    enableStaticWebDeepLinkRecovery: enableRecovery,
    androidStoreUrl: 'https://play.google.com/store/apps/details?id=com.test',
    iosStoreUrl: 'https://apps.apple.com/app/test',
    breakpoints: AppBreakpoints(tabletFromWidth: 600, desktopFromWidth: 900),
    colors: AppColors(
      seedColor: const Color(0xFF0000FF),
      primaryColor: const Color(0xFFFF0000),
    ),
  );
}

void main() {
  group('deriveInitialWebAppUri', () {
    test('keeps the current browser URI when recovery is disabled', () {
      final browserUri = Uri.parse('https://test.example.com/web/');

      final initialUri = deriveInitialWebAppUri(
        browserUri,
        config: _testConfig(enableRecovery: false),
        recoveredPath: '/web/song/song-123',
      );

      expect(initialUri, browserUri);
    });

    test('uses the recovered deep link when recovery is enabled', () {
      final browserUri = Uri.parse('https://test.example.com/web/');

      final initialUri = deriveInitialWebAppUri(
        browserUri,
        config: _testConfig(enableRecovery: true),
        recoveredPath: '/web/song/song-123?view=lyrics#verse-2',
      );

      expect(
        initialUri.toString(),
        'https://test.example.com/web/song/song-123?view=lyrics#verse-2',
      );
    });
  });
}
