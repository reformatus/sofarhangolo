import 'dart:convert';

import 'package:mailto/mailto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../config/config.dart';
import 'platform_info.dart';

Future sendFeedbackEmail({String? errorMessage, String? stackTrace}) async {
  JsonEncoder encoder = JsonEncoder.withIndent('  ', (o) {
    try {
      return o.toJson();
    } catch (_) {
      return o.toString();
    }
  });
  PackageInfo packageInfo = await PackageInfo.fromPlatform();

  final String exceptionString = errorMessage == null
      ? ''
      : '''
[HIBA]
$errorMessage
${stackTrace?.split('\n').take(6).join('\n')}

''';

  Map<String, dynamic>? platformInfo;
  try {
    platformInfo = await collectFeedbackPlatformInfo(packageInfo);
  } catch (_) {}

  final String subject = errorMessage == null
      ? 'Visszajelzés'
      : 'Hibajelentés: $errorMessage';

  Mailto mail = Mailto(
    to: [appConfig.appFeedbackEmail],
    subject:
        '$subject - Lyric ${packageInfo.version}+${packageInfo.buildNumber}',
    body:
        '''
Írd le, mit tapasztaltál:




---------------
Az alábbi adatokat ne töröld ki, ha hibát jelentesz:
$exceptionString
[APP INFO]
${encoder.convert(packageInfo.data)}

[PLATFORM INFO]
${encoder.convert(platformInfo)}
''',
  );

  launchUrl(Uri.parse(mail.toString()));
}
