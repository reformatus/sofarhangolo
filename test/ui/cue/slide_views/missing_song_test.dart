import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/song/song_content.dart';
import 'package:sofarhangolo/ui/cue/slide_views/song.dart';
import 'package:sofarhangolo/ui/song/state.dart';

void main() {
  testWidgets('a missing song renders the error state, not a crash', (
    tester,
  ) async {
    const songUuid = 'gone-song';
    final slide = SongSlide(
      'slide-1',
      songUuid,
      null,
      viewType: SongViewType.lyrics,
      sharedTitle: 'Eltűnt dal',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songContentProvider(songUuid).overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SongSlideView(slide, 'cue-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A dal nem található'), findsOneWidget);
  });

  testWidgets('a present song renders normally', (tester) async {
    const songUuid = 'present-song';
    final song = Song.fromBankApiJson({
      'uuid': songUuid,
      'title': 'Megvan',
      'lyrics': 'Szent vagy, szent vagy',
    });
    final slide = SongSlide(
      'slide-1',
      songUuid,
      null,
      song: song,
      viewType: SongViewType.lyrics,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songContentProvider(songUuid).overrideWith(
            (ref) => Stream.value(SongSnapshot(song, song.contentHash)),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SongSlideView(slide, 'cue-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A dal nem található'), findsNothing);
  });
}
