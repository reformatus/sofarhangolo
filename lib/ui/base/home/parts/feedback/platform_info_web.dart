import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web/web.dart' as web;

Future<Map<String, dynamic>?> collectFeedbackPlatformInfo(
  PackageInfo packageInfo,
) async {
  final navigator = web.window.navigator;
  final location = web.window.location;

  return {
    'platform': 'web',
    'packageInfo': packageInfo.data,
    'buildMode': {
      'debug': kDebugMode,
      'profile': kProfileMode,
      'release': kReleaseMode,
    },
    'browser': {
      'userAgent': navigator.userAgent,
      'appCodeName': navigator.appCodeName,
      'appName': navigator.appName,
      'appVersion': navigator.appVersion,
      'language': navigator.language,
      'platformHint': navigator.platform,
      'vendor': navigator.vendor,
      'cookieEnabled': navigator.cookieEnabled,
      'online': navigator.onLine,
      'hardwareConcurrency': navigator.hardwareConcurrency,
      'maxTouchPoints': navigator.maxTouchPoints,
    },
    'location': {
      'href': location.href,
      'origin': location.origin,
      'pathname': location.pathname,
      'search': location.search,
      'hash': location.hash,
    },
    'document': {
      'referrer': web.document.referrer,
      'title': web.document.title,
      'visibilityState': web.document.visibilityState,
    },
  };
}
