import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/log/logger.dart';
import '../../ui/song/state.dart';
import '../ui/messenger_service.dart';
import 'providers/general.dart';
import 'providers/lyrics_view_style.dart';
import 'providers/song_view_order.dart';

part 'classes/general.dart';
part 'classes/lyrics_view_style.dart';
part 'classes/song_view_order.dart';

sealed class PreferencesParentClass<T extends PreferencesParentClass<T>> {
  String key;
  PreferencesParentClass(this.key);

  /// Abstract method for subclasses to provide their fromJson factory
  T fromJson(Map<String, dynamic>? json);

  /// Initialize self from database
  Future<T> getFromDb() async {
    final json = await _getJsonFromDb();
    return fromJson(json);
  }

  Future<Map<String, dynamic>?> _getJsonFromDb() async {
    final json =
        (await (db.preferenceStorage.select()..where((p) => p.key.equals(key)))
                .getSingleOrNull())
            ?.value;
    return json;
  }

  Map<String, dynamic> toJson();

  /// Write self to database
  Future writeToDb() async {
    try {
      await db
          .into(db.preferenceStorage)
          .insert(
            PreferenceStorageCompanion(key: Value(key), value: Value(toJson())),
            mode: InsertMode.insertOrReplace,
          );
    } catch (e, s) {
      log.severe('Beállítások: Nem sikerült $key mentése!', e, s);
    }
  }
}

Future<void> loadAllPreferences(WidgetRef ref) async {
  await Future.wait([
    ref.read(generalPreferencesProvider.notifier).loadFromDb(),
    ref.read(lyricsViewStylePreferencesProvider.notifier).loadFromDb(),
    ref.read(songViewOrderPreferencesProvider.notifier).loadFromDb(),
  ]);

  return;
}

enum PreferenceClasses {
  general(GeneralPreferencesClass),
  lyricsViewStyle(LyricsViewStylePreferencesClass),
  songViewOrder(SongViewOrderPreferencesClass);

  final Type type;
  const PreferenceClasses(this.type);

  // TODO remove if unnecessary
  NotifierProvider get provider =>
      switch (this) {
            general => generalPreferencesProvider,
            lyricsViewStyle => lyricsViewStylePreferencesProvider,
            songViewOrder => songViewOrderPreferencesProvider,
          }
          as NotifierProvider;

  static PreferenceClasses fromModel<T extends PreferencesParentClass<T>>(
    T preferenceClass,
  ) => switch (preferenceClass) {
    GeneralPreferencesClass() => general,
    LyricsViewStylePreferencesClass() => lyricsViewStyle,
    SongViewOrderPreferencesClass() => songViewOrder,
  };
}
