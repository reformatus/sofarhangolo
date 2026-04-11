import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/log/logger.dart';
import '../../ui/messenger_service.dart';
import '../preferences_parent.dart';

part 'lyrics_view_style.g.dart';

@Riverpod(keepAlive: true)
class LyricsViewStylePreferences extends _$LyricsViewStylePreferences {
  @override
  LyricsViewStylePreferencesClass build() {
    return LyricsViewStylePreferencesClass(
      chordsSize: 16,
      lyricsSize: 16,
      verseTagSize: 16,
      verseCardColumnWidth: 350,
    );
  }

  Future<void> loadFromDb() async {
    state = await state.getFromDb();
  }

  Future<void> go() async {
    ref.notifyListeners();
    try {
      await state.writeToDb();
    } catch (e, s) {
      log.severe('Nem sikerült a dalszövegstílus-beállítások mentése!', e, s);
    }
  }

  void setChordsSize(double newValue) {
    state.chordsSize = newValue;
    go();
  }

  void setLyricsSize(double newValue) {
    state.lyricsSize = newValue;
    go();
  }

  void setVerseTagSize(double newValue) {
    state.verseTagSize = newValue;
    go();
  }

  void setVerseCardColumnWidth(int newValue) {
    state.verseCardColumnWidth = newValue;
    go();
  }

  void reset() {
    double defaultFontSize =
        Theme.of(messengerService.context!).textTheme.bodyMedium?.fontSize ??
        17;
    state.chordsSize = defaultFontSize;
    state.lyricsSize = defaultFontSize;
    state.verseTagSize = defaultFontSize;
    state.verseCardColumnWidth = 350; // far future todo: factor out
    go();
  }
}
