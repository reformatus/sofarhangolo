import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/services/ui/presentation_fullscreen_shared.dart';
import 'package:sofarhangolo/services/ui/presentation_fullscreen_stub.dart';

class _RecordingNativeFullscreenDriver implements NativeFullscreenDriver {
  final calls = <({bool enabled, SystemUiMode? systemUiMode})>[];

  @override
  Future<void> setFullScreen(bool enabled, {SystemUiMode? systemUiMode}) async {
    calls.add((enabled: enabled, systemUiMode: systemUiMode));
  }
}

void main() {
  group('PlatformPresentationFullscreenController', () {
    test('keeps native fullscreen entry behavior unchanged', () async {
      final driver = _RecordingNativeFullscreenDriver();
      final controller = PlatformPresentationFullscreenController(
        driver: driver,
      );

      await controller.enter();

      expect(driver.calls, [
        (enabled: true, systemUiMode: SystemUiMode.edgeToEdge),
      ]);
    });

    test('keeps native fullscreen exit behavior unchanged', () async {
      final driver = _RecordingNativeFullscreenDriver();
      final controller = PlatformPresentationFullscreenController(
        driver: driver,
      );

      await controller.exit();

      expect(driver.calls, [(enabled: false, systemUiMode: null)]);
    });

    test('tracks fullscreen state changes for native flow', () async {
      final driver = _RecordingNativeFullscreenDriver();
      final controller = PlatformPresentationFullscreenController(
        driver: driver,
      );
      final states = <bool>[];
      final subscription = controller.changes.listen(states.add);

      expect(controller.isFullscreen, isFalse);

      await controller.enter();
      await controller.exit();
      await Future<void>.delayed(Duration.zero);

      expect(controller.isFullscreen, isFalse);
      expect(states, [true, false]);

      await subscription.cancel();
    });
  });
}
