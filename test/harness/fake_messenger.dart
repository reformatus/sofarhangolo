import 'package:flutter/material.dart';
import 'package:sofarhangolo/services/ui/messenger_service.dart';

/// A fake [MessengerService] that records calls for test assertions.
///
/// Use this to verify snackbars/banners are shown without needing
/// a real ScaffoldMessenger widget tree.
class FakeMessengerService extends MessengerService {
  final List<SnackBar> shownSnackBars = [];
  final List<MaterialBanner> shownBanners = [];
  int clearBannersCalled = 0;
  int hideCurrentBannerCalled = 0;

  FakeMessengerService() : super(scaffoldMessengerKey: null);

  @override
  ScaffoldMessengerState? get state => null;

  @override
  BuildContext? get context => null;

  @override
  void showSnackBar(SnackBar snackBar) {
    shownSnackBars.add(snackBar);
  }

  @override
  void clearBanners() {
    clearBannersCalled++;
  }

  @override
  void showBanner(MaterialBanner banner) {
    shownBanners.add(banner);
  }

  @override
  void hideCurrentBanner() {
    hideCurrentBannerCalled++;
  }

  /// Reset all recorded state for reuse across tests.
  void reset() {
    shownSnackBars.clear();
    shownBanners.clear();
    clearBannersCalled = 0;
    hideCurrentBannerCalled = 0;
  }
}
