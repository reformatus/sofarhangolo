import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/ui/base/widgets/active_cue_shell_card.dart';
import 'package:sofarhangolo/ui/cue/session/cue_session.dart';
import 'package:sofarhangolo/ui/song/state.dart';

import '../../harness/test_database.dart';

Song _createSong(String uuid, String title) {
  return Song.fromBankApiJson({
    'uuid': uuid,
    'title': title,
    'lyrics': '<song><lyrics>$title</lyrics></song>',
    'lyricsFormat': 'opensong',
  });
}

Future<void> _insertSong(Song song) async {
  await db.into(db.songs).insert(song, mode: InsertMode.insertOrReplace);
}

void main() {
  late LyricDatabase testDb;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
  });

  tearDown(() async {
    await testDb.close();
  });

  testWidgets('shows added state instead of add button for current cue song', (
    tester,
  ) async {
    final song = _createSong('song-1', 'Song');
    await _insertSong(song);

    final cue = Cue(1, 'cue-1', 'Cue', 'Desc', currentCueVersion, const []);
    cue.replaceSlides([SongSlide.from(song, viewType: SongViewType.lyrics)]);
    final session = CueSession(
      cue: cue,
      currentSlideUuid: cue.slides.single.uuid,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ActiveCueShellCard(
              session: session,
              currentPath: '/song/${song.uuid}',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hozzáadva'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Hozzáadás'), findsNothing);
  });
}
