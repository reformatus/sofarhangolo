import 'package:web/web.dart' as web;

void restoreStoredWebRouteIfAny() {
  final storedPath = web.window.sessionStorage.getItem('originalWebPath');
  if (storedPath == null || storedPath.isEmpty) {
    return;
  }

  web.window.history.replaceState(null, '', storedPath);
  web.window.sessionStorage.removeItem('originalWebPath');
}
