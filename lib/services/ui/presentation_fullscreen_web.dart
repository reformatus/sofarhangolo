import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'presentation_fullscreen_shared.dart';

class PlatformPresentationFullscreenController
    implements PresentationFullscreenController {
  PlatformPresentationFullscreenController() {
    _fullscreenChangeListener = ((web.Event _) {
      _changes.add(isFullscreen);
    }).toJS;

    web.document.addEventListener(
      'fullscreenchange',
      _fullscreenChangeListener,
    );
  }

  late final JSFunction _fullscreenChangeListener;
  final _changes = StreamController<bool>.broadcast();

  @override
  bool get isFullscreen => web.document.fullscreenElement != null;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<void> prepareForNavigation() async {
    await web.document.documentElement?.requestFullscreen().toDart;
  }

  @override
  Future<void> enter() async {}

  @override
  Future<void> exit() async {
    if (web.document.fullscreenElement != null) {
      await web.document.exitFullscreen().toDart;
    }
  }
}

PresentationFullscreenController createPresentationFullscreenController() {
  return PlatformPresentationFullscreenController();
}
