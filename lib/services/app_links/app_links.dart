import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import '../../config/config.dart';
import '../cue/import_from_link.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/log/logger.dart';
import 'navigation.dart';
import 'web_initial_uri.dart';

part 'app_links.g.dart';

final appLinksSingleton = AppLinks();
Uri? _initialAppUri;

Future<Uri?> captureInitialAppUri() async {
  if (_initialAppUri != null) {
    return _initialAppUri;
  }

  if (kIsWeb) {
    _initialAppUri = takeStoredWebInitialUri() ?? Uri.base;
  } else {
    _initialAppUri = await appLinksSingleton.getInitialLink();
  }

  return _initialAppUri;
}

@Riverpod(keepAlive: true)
Stream<String> shouldNavigate(Ref ref) async* {
  if (kIsWeb) {
    return;
  }

  final initialUri = _initialAppUri;
  var skippedInitialUri = initialUri == null;

  await for (Uri uri in appLinksSingleton.uriLinkStream) {
    log.info(
      'Bejövő link kezelése: "${uri.toString().substring(0, uri.toString().length.clamp(0, 100))}"',
    );
    try {
      if (!skippedInitialUri && uri.toString() == initialUri.toString()) {
        skippedInitialUri = true;
        continue;
      }
      skippedInitialUri = true;

      if (uri.scheme != appConfig.urlScheme &&
          uri.authority != appConfig.domain) {
        continue;
      }

      final route = appRouteFromUri(uri);
      if (route == null) continue;

      final routeUri = Uri.parse(route);
      switch (routeUri.path) {
        case '/launch/cueData':
          final encodedData = routeUri.queryParameters['data'];
          if (encodedData == null) continue;
          final result = await importCueFromCompressedData(
            encodedData,
            routeUri.queryParameters,
          );
          yield result.getNavigationPath();
        case '/launch/cueJson':
          final jsonString = routeUri.queryParameters['data'];
          if (jsonString == null) continue;
          final result = await importCueFromJson(
            jsonString,
            routeUri.queryParameters,
          );
          yield result.getNavigationPath();
        default:
          yield route;
      }
    } catch (e, s) {
      log.severe('Hiba egy link megnyitása közben', e, s);
    }
  }
}
