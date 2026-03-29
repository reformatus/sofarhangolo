import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import '../../config/config.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/log/logger.dart';
import 'launch_resolution.dart';

part 'app_links.g.dart';

final appLinksSingleton = AppLinks();
Uri? _initialAppUri;

Future<Uri?> captureInitialAppUri() async {
  if (_initialAppUri != null) {
    return _initialAppUri;
  }

  if (kIsWeb) return null;

  _initialAppUri = await appLinksSingleton.getInitialLink();

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

      final route = await resolveIncomingAppRoute(uri);
      if (route == null) continue;
      yield route;
    } catch (e, s) {
      log.severe('Hiba egy link megnyitása közben', e, s);
    }
  }
}
