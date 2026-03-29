import '../../config/app_config.dart';
import '../../config/config.dart';
import '../../ui/cue/cue_page_type.dart';

String songRoutePath(String songUuid) =>
    _routeString(pathSegments: ['song', songUuid]);

String cueRoutePath(String cueUuid, CuePageType pageType, {String? slideUuid}) {
  final pathSegments = switch (pageType) {
    CuePageType.edit => ['cue', cueUuid, 'edit'],
    CuePageType.musician => ['cue', cueUuid, 'present', 'musician'],
  };

  return _routeString(
    pathSegments: pathSegments,
    queryParameters: {
      if (slideUuid != null && slideUuid.isNotEmpty) 'slide': slideUuid,
    },
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
        pathSegments: ['song', pathSegments[2]],
        query: query,
        fragment: fragment,
      );
    }

    return _routeString(
      pathSegments: pathSegments,
      query: query,
      fragment: fragment,
    );
  }

  return _routeString(
    pathSegments: pathSegments,
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

String _routeString({
  required List<String> pathSegments,
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
    path: '/${pathSegments.join('/')}',
    queryParameters: normalizedQueryParameters,
    query: normalizedQuery,
    fragment: normalizedFragment,
  ).toString();
}
