import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/connectivity/provider.dart';
import 'package:sofarhangolo/services/preferences/preferences_parent.dart';
import 'package:sofarhangolo/services/preferences/providers/song_view_order.dart';
import 'package:sofarhangolo/ui/song/state.dart';

import '../../harness/test_harness.dart';

Song _createChordedSong() {
  return Song(
    uuid: 'song-1',
    title: 'Chorded Song',
    lyrics: '<song>\n[V1]\n.C    G\n Hello world\n</song>',
    keyField: [],
    contentMap: {},
  );
}

void main() {
  test(
    'viewTypeForProvider prefers chords over lyrics when the song has chords',
    () async {
      final container = createTestContainer(
        additionalOverrides: [
          connectionProvider.overrideWithValue(ConnectionType.unlimited),
          songViewOrderPreferencesProvider.overrideWithValue(
            SongViewOrderPreferencesClass(
              songViewOrder: [SongViewType.lyrics, SongViewType.chords],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final viewType = await container.read(
        viewTypeForProvider(_createChordedSong(), null).future,
      );

      expect(viewType, SongViewType.chords);
    },
  );
}
