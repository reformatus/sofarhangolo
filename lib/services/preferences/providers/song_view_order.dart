import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/log/logger.dart';
import '../preferences_parent.dart';

part 'song_view_order.g.dart';

@Riverpod(keepAlive: true)
class SongViewOrderPreferences extends _$SongViewOrderPreferences {
  @override
  SongViewOrderPreferencesClass build() {
    return SongViewOrderPreferencesClass(songViewOrder: []);
  }

  Future<void> loadFromDb() async {
    state = await state.getFromDb();
  }

  Future<void> go() async {
    ref.notifyListeners();
    try {
      await state.writeToDb();
    } catch (e, s) {
      log.severe('Nem sikerült az alapértelmezett nézet mentése!', e, s);
    }
  }

  void reorder(int oldIndex, int newIndex) {
    final newOrder = [...state.songViewOrder];
    final item = newOrder.removeAt(oldIndex);
    newOrder.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);

    state = SongViewOrderPreferencesClass(songViewOrder: newOrder);
    go();
  }
}
