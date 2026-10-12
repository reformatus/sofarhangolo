import 'package:dart_opensong/dart_opensong.dart' as os;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/transpose.dart';
import 'package:sofarhangolo/ui/song/lyrics/view.dart';

import '../../../harness/test_harness.dart';

/// A chord line whose leading indentation makes the parser emit a chordless
/// segment (the leading text) followed by a chorded one - see the alignment
/// fix in [LyricsSegment].
const _lyrics = '''
[V1]
.        C
 Az összetört világért tűrted,
''';

void main() {
  late LyricDatabase testDb;
  late TestHarness harness;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    harness = TestHarness();
  });

  tearDown(() async {
    harness.dispose();
    await testDb.close();
  });

  Future<void> pumpVerse(WidgetTester tester) async {
    final verse = os.getVersesFromString(_lyrics).first;
    final song = Song(
      uuid: 'song-1',
      title: 'Dal',
      lyrics: _lyrics,
      keyField: const [],
      contentMap: const {},
      sourceBank: 'bank-1',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final part in verse.parts)
                    if (part is os.VerseLine)
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.start,
                        children: [
                          for (final segment in part.segments)
                            LyricsSegment(
                              song: song,
                              transpose: SongTranspose(),
                              segments: part.segments,
                              segment: segment,
                            ),
                        ],
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The first [Text] inside segment [index] is its chord slot, the second is
  /// its lyrics.
  Rect textRect(WidgetTester tester, int index, int child) {
    final texts = find.descendant(
      of: find.byType(LyricsSegment).at(index),
      matching: find.byType(Text),
    );
    return tester.getRect(texts.at(child));
  }

  testWidgets('chordless and chorded segments of a line stay flush', (
    tester,
  ) async {
    await pumpVerse(tester);

    final widgetCount = find.byType(LyricsSegment).evaluate().length;
    expect(widgetCount, 2);
    expect(
      tester.widget<LyricsSegment>(find.byType(LyricsSegment).first).segment.chord,
      isNull,
      reason: 'the leading indentation must produce a chordless segment',
    );

    // Equal height, and the lyrics share one top: a chord in one segment must
    // not shift that segment's lyrics relative to its neighbours.
    final first = tester.getSize(find.byType(LyricsSegment).at(0));
    final second = tester.getSize(find.byType(LyricsSegment).at(1));
    expect(first.height, second.height);
    expect(
      textRect(tester, 0, 1).top,
      textRect(tester, 1, 1).top,
      reason: 'lyrics of the line must share a baseline',
    );

    // The chorded segment's chord hangs above its own lyrics.
    expect(textRect(tester, 1, 0).top, lessThan(textRect(tester, 1, 1).top));
  });
}
