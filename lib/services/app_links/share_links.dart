import '../../config/app_config.dart';
import '../../config/config.dart';
import '../../data/cue/cue.dart';
import '../../data/song/song.dart';
import '../cue/compression.dart';

Uri getShareableSongLink(Song song, {AppConfig? config}) {
  config ??= appConfig;
  return _homepageUri(config, pathSegments: ['launch', 'song', song.uuid]);
}

Uri getShareableCueLink(Cue cue, {AppConfig? config}) {
  config ??= appConfig;
  return _homepageUri(
    config,
    pathSegments: ['launch', 'cueData'],
    queryParameters: {'data': compressCueForUrl(cue.toJson())},
  );
}

Uri _homepageUri(
  AppConfig config, {
  required List<String> pathSegments,
  Map<String, String>? queryParameters,
}) {
  final baseUri = Uri.parse(config.homepageRoot);
  final baseSegments = baseUri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();

  return baseUri.replace(
    pathSegments: [...baseSegments, ...pathSegments],
    queryParameters: queryParameters,
  );
}
