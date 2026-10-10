import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/song/song.dart';
import '../../ui/base/songs/widgets/filter/types/key/state.dart';
import '../songs/facet.dart';

part 'filter.g.dart';

typedef KeyFilterSelectable = ({
  String label,
  Function(bool) onSelected,
  bool selected,
  bool addingKey,
});

/// Pitch or complete-key chips the key card offers, limited to the keys that
/// still match the current query (see [keyFacet]). When a single mode is
/// selected the row narrows to the complete keys carrying it.
@riverpod
Future<List<KeyFilterSelectable>> selectablePitches(Ref ref) async {
  // Captured once: the provider rebuilds with a fresh Ref, so a chip rendered
  // from a previous value must not reach back through that provider's ref when
  // it is tapped.
  final keyFilterState = ref.read(keyFilterStateProvider.notifier);
  final state = ref.watch(keyFilterStateProvider);
  final available = await ref.watch(keyFacetProvider.future);

  if (state.modes.length == 1 && state.pitches.isEmpty) {
    return [
      for (final key in _sortedKeys(available.keys))
        if (key.mode == state.modes.first && !state.keys.contains(key))
          (
            label: key.toString(),
            onSelected: (bool v) => keyFilterState.setKeyTo(key, v),
            selected: false,
            addingKey: true,
          ),
    ];
  }

  return [
    for (final pitch in _sorted(available.pitches))
      (
        label: pitch,
        onSelected: (bool v) => keyFilterState.setPitchTo(pitch, v),
        selected: state.pitches.contains(pitch),
        addingKey: false,
      ),
  ];
}

/// Mode or complete-key chips the key card offers, limited to the keys that
/// still match the current query (see [keyFacet]). When a single pitch is
/// selected the row narrows to the complete keys carrying it.
@riverpod
Future<List<KeyFilterSelectable>> selectableModes(Ref ref) async {
  final keyFilterState = ref.read(keyFilterStateProvider.notifier);
  final state = ref.watch(keyFilterStateProvider);
  final available = await ref.watch(keyFacetProvider.future);

  if (state.pitches.length == 1 && state.modes.isEmpty) {
    return [
      for (final key in _sortedKeys(available.keys))
        if (key.pitch == state.pitches.first && !state.keys.contains(key))
          (
            label: key.toString(),
            onSelected: (bool v) => keyFilterState.setKeyTo(key, v),
            selected: false,
            addingKey: true,
          ),
    ];
  }

  return [
    for (final mode in _sorted(available.modes))
      (
        label: mode,
        onSelected: (bool v) => keyFilterState.setModeTo(mode, v),
        selected: state.modes.contains(mode),
        addingKey: false,
      ),
  ];
}

List<String> _sorted(Iterable<String> values) => values.toList()..sort();

List<KeyField> _sortedKeys(Iterable<KeyField> keys) {
  final list = keys.toList()
    ..sort((a, b) {
      final byPitch = a.pitch.compareTo(b.pitch);
      return byPitch != 0 ? byPitch : a.mode.compareTo(b.mode);
    });
  return list;
}
