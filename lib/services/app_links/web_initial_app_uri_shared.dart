import '../../config/app_config.dart';

Uri deriveInitialWebAppUri(
  Uri browserUri, {
  required AppConfig config,
  String? recoveredPath,
}) {
  if (!config.enableStaticWebDeepLinkRecovery ||
      recoveredPath == null ||
      recoveredPath.isEmpty) {
    return browserUri;
  }

  final normalizedRecoveredPath = recoveredPath.startsWith('/')
      ? recoveredPath
      : '/$recoveredPath';

  return browserUri.resolveUri(Uri.parse(normalizedRecoveredPath));
}
