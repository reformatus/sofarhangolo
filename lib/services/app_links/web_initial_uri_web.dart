import 'dart:html' as html;

Uri? takeStoredWebInitialUri() {
  final storedPath = html.window.sessionStorage['originalWebPath'];
  if (storedPath == null || storedPath.isEmpty) {
    return null;
  }

  html.window.history.replaceState(null, '', storedPath);
  html.window.sessionStorage.remove('originalWebPath');
  return Uri.base.resolve(storedPath);
}
