import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sofarhangolo/services/http/dio_provider.dart';
import 'package:sofarhangolo/services/platform/platform_provider.dart';
import 'package:sofarhangolo/services/ui/messenger_service.dart';

import 'fake_messenger.dart';
import 'fake_platform.dart';
import 'mock_dio.dart';

export 'fake_messenger.dart';
export 'fake_platform.dart';
export 'mock_dio.dart';
export 'test_config.dart';
export 'test_database.dart';

/// Creates a [ProviderContainer] with common test overrides pre-configured.
///
/// Use this for unit testing services and providers without a widget tree.
///
/// Example:
/// ```dart
/// final container = createTestContainer();
/// final dio = container.read(dioProvider);
/// // dio is now the mock instance
/// ```
ProviderContainer createTestContainer({
  FakeMessengerService? fakeMessenger,
  PlatformInfo? fakePlatform,
  List<dynamic> additionalOverrides = const [],
}) {
  final messenger = fakeMessenger ?? FakeMessengerService();
  final platform = fakePlatform ?? createTestPlatformInfo();
  final mockDio = createMockDio();

  return ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(mockDio),
      platformInfoProvider.overrideWithValue(platform),
      messengerServiceProviderProvider.overrideWithValue(messenger),
      ...additionalOverrides,
    ],
  );
}

/// A test harness that manages test dependencies lifecycle.
///
/// Provides easy access to fakes and handles cleanup automatically.
/// Use in setUp/tearDown for consistent test isolation.
///
/// Example:
/// ```dart
/// late TestHarness harness;
///
/// setUp(() {
///   harness = TestHarness();
/// });
///
/// tearDown(() {
///   harness.dispose();
/// });
///
/// test('shows snackbar on error', () {
///   // ... trigger action that shows snackbar
///   expect(harness.messenger.shownSnackBars, hasLength(1));
/// });
/// ```
class TestHarness {
  TestHarness({
    PlatformInfo? platform,
    List<dynamic> additionalOverrides = const [],
  }) {
    messenger = FakeMessengerService();
    this.platform = platform ?? createTestPlatformInfo();
    mockDio = createMockDio();

    container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(mockDio),
        platformInfoProvider.overrideWithValue(this.platform),
        messengerServiceProviderProvider.overrideWithValue(messenger),
        ...additionalOverrides,
      ],
    );
  }

  late final FakeMessengerService messenger;
  late final PlatformInfo platform;
  late final ProviderContainer container;
  late final Dio mockDio;

  /// Reset all fakes to initial state (call between test cases if reusing harness).
  void reset() {
    messenger.reset();
  }

  /// Dispose resources. Call in tearDown.
  void dispose() {
    container.dispose();
  }
}
