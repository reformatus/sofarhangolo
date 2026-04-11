import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get globalContext;

Future<String> fetchGithubReleasesJson(String repoPath) async {
  final fetchFn = globalContext.getProperty('sofarFetchGithubReleases'.toJS);
  if (fetchFn == null || fetchFn.isUndefinedOrNull) {
    throw StateError('sofarFetchGithubReleases is not available.');
  }

  final promise = (fetchFn as JSFunction).callAsFunction(
    globalContext,
    repoPath.toJS,
  );
  if (promise == null || promise.isUndefinedOrNull) {
    throw StateError('GitHub release request returned no result.');
  }

  return (promise as JSPromise<JSString>).toDart.then((value) => value.toDart);
}
