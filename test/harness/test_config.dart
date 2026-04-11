import 'package:flutter/material.dart';
import 'package:sofarhangolo/config/app_config.dart';

/// Test configuration with predictable values for assertions.
/// Use this in unit tests instead of the production appConfig.
final testAppConfig = AppConfig(
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
  androidStoreUrl: 'https://play.google.com/store/apps/details?id=com.test',
  iosStoreUrl: 'https://apps.apple.com/app/test',
  breakpoints: AppBreakpoints(tabletFromWidth: 600, desktopFromWidth: 900),
  colors: AppColors(
    seedColor: const Color(0xFF0000FF),
    primaryColor: const Color(0xFFFF0000),
  ),
);
