import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

Future<Map<String, dynamic>?> collectFeedbackPlatformInfo(
  PackageInfo packageInfo,
) async {
  return {
    'packageInfo': packageInfo.data,
    //'environment': Platform.environment,
    'executable:': Platform.executable,
    'executableArguments': Platform.executableArguments,
    'localHostname': Platform.localHostname,
    'localeName': Platform.localeName,
    'numberOfProcessors': Platform.numberOfProcessors,
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'packageConfig': Platform.packageConfig,
    'resolvedExecutable': Platform.resolvedExecutable,
    'script': Platform.script,
    'dart-version': Platform.version,
  };
}
