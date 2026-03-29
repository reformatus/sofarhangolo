import 'package:flutter/material.dart';

class AppBreakpoints {
  final double tabletFromWidth;
  final double desktopFromWidth;

  const AppBreakpoints({
    required this.tabletFromWidth,
    required this.desktopFromWidth,
  });
}

class AppColors {
  final Color seedColor;
  final Color primaryColor;

  const AppColors({required this.seedColor, required this.primaryColor});
}

class AppConfig {
  final String appName;
  final String organisationName;
  final String gitHubApiRoot;
  final String domain;
  final String appFeedbackEmail;
  final String homepageRoot;
  final String apiRoot;
  final String webappRoot;
  final String gitHubRepo;
  final String newsRss;
  final String buttonsRss;
  final String urlScheme;
  final bool enableStaticWebDeepLinkRecovery;
  final String? androidStoreUrl;
  final String? iosStoreUrl;
  final AppBreakpoints breakpoints;
  final AppColors colors;

  const AppConfig({
    required this.appName,
    required this.organisationName,
    required this.gitHubApiRoot,
    required this.domain,
    required this.appFeedbackEmail,
    required this.homepageRoot,
    required this.apiRoot,
    required this.webappRoot,
    required this.gitHubRepo,
    required this.newsRss,
    required this.buttonsRss,
    required this.urlScheme,
    this.enableStaticWebDeepLinkRecovery = false,
    required this.androidStoreUrl,
    required this.iosStoreUrl,
    required this.breakpoints,
    required this.colors,
  });
}
