import 'package:sofarhangolo/services/platform/platform_provider.dart';

/// Creates a [PlatformInfo] with overridable values for testing.
///
/// Defaults to desktop (non-web, non-mobile) for predictable test behavior.
PlatformInfo createTestPlatformInfo({
  bool isWeb = false,
  bool isMobile = false,
  bool isDesktop = true,
}) {
  return PlatformInfo(isWeb: isWeb, isMobile: isMobile, isDesktop: isDesktop);
}
