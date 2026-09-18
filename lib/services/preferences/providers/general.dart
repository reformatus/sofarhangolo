import 'package:flutter/material.dart';
import '../preferences_parent.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/log/logger.dart';

part 'general.g.dart';

@Riverpod(keepAlive: true)
class GeneralPreferences extends _$GeneralPreferences {
  @override
  GeneralPreferencesClass build() {
    // Values here don't matter (defaults are in the fromJson factory)
    // far future todo: can this be removed and default values provided from the outside?
    return GeneralPreferencesClass(
      appBrightness: ThemeMode.system,
      sheetBrightness: ThemeMode.light,
      oledBlackBackground: false,
      testingMode: false,
    );
  }

  Future<void> loadFromDb() async {
    state = await state.getFromDb();
  }

  void go() async {
    ref.notifyListeners();
    try {
      await state.writeToDb();
    } catch (e, s) {
      log.severe('Nem sikerült az általános beállítások mentése!', e, s);
    }
  }

  void setAppBrightness(ThemeMode newValue) {
    state.appBrightness = newValue;
    go();
  }

  void setSheetBrightness(ThemeMode newValue) {
    state.sheetBrightness = newValue;
    go();
  }

  void setOledBlackBackground(bool newValue) {
    state.oledBlackBackground = newValue;
    go();
  }

  void setTestingMode(bool newValue) {
    state.testingMode = newValue;
    go();
  }
}
