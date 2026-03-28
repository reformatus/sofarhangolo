import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';
import '../../ui/base/songs/widgets/filter/types/key/state.dart';

part 'filter.g.dart';

typedef KeyFilterSelectable = ({
  String label,
  Function(bool) onSelected,
  bool selected,
  bool addingKey,
});

@Riverpod(keepAlive: true)
Stream<List<KeyFilterSelectable>> selectablePitches(Ref ref) {
  final state = ref.watch(keyFilterStateProvider);
  return db.select(db.songs).watch().map((songs) {
    final selectables = <KeyFilterSelectable>[];
    final seenPitches = <String>{};

    for (final song in songs) {
      for (final key in song.keyField) {
        if (state.modes.length == 1 && state.pitches.isEmpty) {
          if (key.mode != state.modes.first) continue;
          if (!seenPitches.add(key.pitch)) continue;
          final selectableKey = KeyField(key.pitch, key.mode);
          if (state.keys.contains(selectableKey)) continue;
          selectables.add((
            label: selectableKey.toString(),
            onSelected: (v) => ref
                .read(keyFilterStateProvider.notifier)
                .setKeyTo(selectableKey, v),
            selected: state.keys.contains(selectableKey),
            addingKey: true,
          ));
        } else {
          if (!seenPitches.add(key.pitch)) continue;
          selectables.add((
            label: key.pitch,
            onSelected: (v) => ref
                .read(keyFilterStateProvider.notifier)
                .setPitchTo(key.pitch, v),
            selected: state.pitches.contains(key.pitch),
            addingKey: false,
          ));
        }
      }
    }

    return selectables;
  });
}

@Riverpod(keepAlive: true)
Stream<List<KeyFilterSelectable>> selectableModes(Ref ref) {
  final state = ref.watch(keyFilterStateProvider);
  return db.select(db.songs).watch().map((songs) {
    final selectables = <KeyFilterSelectable>[];
    final seenModes = <String>{};

    for (final song in songs) {
      for (final key in song.keyField) {
        if (state.pitches.length == 1 && state.modes.isEmpty) {
          if (key.pitch != state.pitches.first) continue;
          if (!seenModes.add(key.mode)) continue;
          final selectableKey = KeyField(key.pitch, key.mode);
          if (state.keys.contains(selectableKey)) continue;
          selectables.add((
            label: selectableKey.toString(),
            onSelected: (v) => ref
                .read(keyFilterStateProvider.notifier)
                .setKeyTo(selectableKey, v),
            selected: state.keys.contains(selectableKey),
            addingKey: true,
          ));
        } else {
          if (!seenModes.add(key.mode)) continue;
          selectables.add((
            label: key.mode,
            onSelected: (v) => ref
                .read(keyFilterStateProvider.notifier)
                .setModeTo(key.mode, v),
            selected: state.modes.contains(key.mode),
            addingKey: false,
          ));
        }
      }
    }

    return selectables;
  });
}
