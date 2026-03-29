import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_config.dart';

// Forks should edit this file to swap out branding, endpoints, and colors.
final AppConfig appConfig = AppConfig(
  appName: 'Sófár Hangoló',
  organisationName: 'Sófár',
  gitHubApiRoot: 'https://api.github.com/repos/reformatus/lyric',
  domain: 'app.sofarkotta.hu',
  appFeedbackEmail: 'sofarhangolo@fodor.pro',
  homepageRoot: 'https://app.sofarkotta.hu',
  apiRoot: 'https://app.sofarkotta.hu/api',
  webappRoot: 'https://app.sofarkotta.hu/web',
  gitHubRepo: 'https://github.com/reformatus/lyric/',
  newsRss: 'https://sofarhangolo.hu/category/app/aktualis/feed',
  buttonsRss: 'https://sofarhangolo.hu/category/app/linkek/feed',
  urlScheme: 'lyric',
  enableStaticWebDeepLinkRecovery: true,
  androidStoreUrl:
      'https://play.google.com/store/apps/details?id=org.lyricapp.sofar',
  iosStoreUrl:
      'https://apps.apple.com/us/app/s%C3%B3f%C3%A1r-hangol%C3%B3/id6738664835',
  breakpoints: AppBreakpoints(tabletFromWidth: 700, desktopFromWidth: 1000),
  colors: AppColors(
    seedColor: const Color(0xff025462),
    primaryColor: const Color(0xffc3a140),
  ),
);

String? get storeLinkForCurrentPlatform {
  if (kIsWeb) {
    return null;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return appConfig.androidStoreUrl;
    case TargetPlatform.iOS:
      return appConfig.iosStoreUrl;
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return null;
  }
}
