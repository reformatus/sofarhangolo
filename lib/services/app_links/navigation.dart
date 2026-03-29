import '../../config/app_config.dart';
import '../../config/config.dart';
import '../../data/cue/cue.dart';
import '../../data/song/song.dart';
import '../../ui/cue/cue_page_type.dart';
import '../cue/compression.dart';

String songRoutePath(String songUuid) => '/song/$songUuid';

String songLaunchPath(String songUuid) => '/launch/song/$songUuid';

String cueRoutePath(String cueUuid, CuePageType pageType, {String? slideUuid}) {
  final routePath = switch (pageType) {
    CuePageType.edit => '/cue/$cueUuid/edit',
    CuePageType.musician => '/cue/$cueUuid/present/musician',
  };

  return _routeString(
    routePath,
    queryParameters: {
      if (slideUuid != null && slideUuid.isNotEmpty) 'slide': slideUuid,
    },
  );
}

Uri getShareableSongLink(Song song, {AppConfig? config}) {
  config ??= appConfig;
  return _homepageUri(
    config,
    pathSegments: songLaunchPath(
      song.uuid,
    ).split('/').where((e) => e.isNotEmpty).toList(),
  );
}

Uri getShareableCueLink(Cue cue, {AppConfig? config}) {
  config ??= appConfig;
  return _homepageUri(
    config,
    pathSegments: ['launch', 'cueData'],
    queryParameters: {'data': compressCueForUrl(cue.toJson())},
  );
}

String initialRouteFromAppUri(
  Uri? uri, {
  AppConfig? config,
  String fallbackRoute = '/home',
}) {
  config ??= appConfig;
  final route = appRouteFromUri(uri, config: config);
  if (route == null || route == '/' || route == '/loading') {
    return fallbackRoute;
  }
  return route;
}

String? appRouteFromUri(Uri? uri, {AppConfig? config}) {
  config ??= appConfig;
  if (uri == null) return null;

  final pathSegments = _normalizedPathSegments(uri, config);
  if (pathSegments == null || pathSegments.isEmpty) {
    return null;
  }

  final query = uri.query;
  final fragment = uri.fragment.isEmpty ? null : uri.fragment;

  if (pathSegments[0] == 'launch') {
    if (pathSegments.length >= 3 && pathSegments[1] == 'song') {
      return _routeString(
        songRoutePath(pathSegments[2]),
        query: query,
        fragment: fragment,
      );
    }

    return _routeString(
      '/${pathSegments.join('/')}',
      query: query,
      fragment: fragment,
    );
  }

  return _routeString(
    '/${pathSegments.join('/')}',
    query: query,
    fragment: fragment,
  );
}

List<String>? _normalizedPathSegments(Uri uri, AppConfig config) {
  if (!_isAppUri(uri, config)) {
    return null;
  }

  if (uri.scheme == config.urlScheme) {
    if (uri.authority == 'launch') {
      return ['launch', ...uri.pathSegments];
    }
    return uri.pathSegments;
  }

  final webAppBasePath = Uri.parse(
    config.webappRoot,
  ).pathSegments.where((segment) => segment.isNotEmpty).toList();
  final pathSegments = uri.pathSegments.where((segment) => segment.isNotEmpty);
  final normalized = pathSegments.toList();

  if (webAppBasePath.isNotEmpty &&
      normalized.length >= webAppBasePath.length &&
      _matchesPrefix(normalized, webAppBasePath)) {
    return normalized.sublist(webAppBasePath.length);
  }

  return normalized;
}

bool _isAppUri(Uri uri, AppConfig config) {
  if (uri.scheme == config.urlScheme) {
    return true;
  }

  return (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.authority == config.domain;
}

bool _matchesPrefix(List<String> value, List<String> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (value[i] != prefix[i]) return false;
  }
  return true;
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

String _routeString(
  String path, {
  Map<String, String>? queryParameters,
  String? query,
  String? fragment,
}) {
  final normalizedQueryParameters =
      queryParameters == null || queryParameters.isEmpty
      ? null
      : queryParameters;
  final normalizedQuery = (query == null || query.isEmpty) ? null : query;
  final normalizedFragment = (fragment == null || fragment.isEmpty)
      ? null
      : fragment;

  return Uri(
    path: path,
    queryParameters: normalizedQueryParameters,
    query: normalizedQuery,
    fragment: normalizedFragment,
  ).toString();
}
