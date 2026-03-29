import '../cue/import_from_link.dart';
import 'navigation.dart';

Future<String?> resolveIncomingAppRoute(Uri? incomingUri) async {
  final route = appRouteFromUri(incomingUri);
  if (route == null) return null;

  return resolveLaunchRoute(Uri.parse(route));
}

Future<String> resolveLaunchRoute(Uri routeUri) async {
  switch (routeUri.path) {
    case '/launch/cueData':
      final encodedData = routeUri.queryParameters['data'];
      if (encodedData == null) {
        throw Exception('Hiányzik a lista adata a linkből.');
      }
      final result = await importCueFromCompressedData(
        encodedData,
        routeUri.queryParameters,
      );
      return result.getNavigationPath();
    case '/launch/cueJson':
      final jsonString = routeUri.queryParameters['data'];
      if (jsonString == null) {
        throw Exception('Hiányzik a lista adata a linkből.');
      }
      final result = await importCueFromJson(
        jsonString,
        routeUri.queryParameters,
      );
      return result.getNavigationPath();
    default:
      return routeUri.toString();
  }
}
