import 'package:package_info_plus/package_info_plus.dart';

Future<Map<String, dynamic>?> collectFeedbackPlatformInfo(
  PackageInfo packageInfo,
) async => {'platform': 'unknown', 'packageInfo': packageInfo.data};
