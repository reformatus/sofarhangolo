import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/lyrics/format.dart';
import 'package:sofarhangolo/data/song/lyrics/parser.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/transpose.dart';
import 'package:sofarhangolo/ui/song/lyrics/theme.dart';
import 'package:sofarhangolo/ui/song/lyrics/view.dart';

void main() {
  const lyrics = '[V1]\nSzállnak az ég felé';

  Song song() => Song(
    uuid: 's1',
    title: 'Teszt dal',
    lyrics: lyrics,
    keyField: const [],
    contentMap: const {},
  );

  OpenSongVerse verse() =>
      LyricsParser.forFormat(LyricsFormat.opensong).parse(lyrics).single
          as OpenSongVerse;

  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.black,
    brightness: Brightness.dark,
  );

  Future<void> pumpVerse(WidgetTester tester, LyricsTheme lyricsTheme) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.from(colorScheme: scheme)
              .copyWith(extensions: [lyricsTheme]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: VerseCard(
                song(),
                verse(),
                transpose: SongTranspose(),
                verseIndex: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('standard look keeps the verse card and the colored tag chip', (
    tester,
  ) async {
    await pumpVerse(tester, LyricsTheme.standard(scheme));

    expect(tester.widget<Card>(find.byType(Card)).color, scheme.onPrimary);

    final tag = tester.widget<Text>(find.text('Versszak 1'));
    expect(tag.style!.color, scheme.onPrimary);
    expect(tag.style!.fontWeight, FontWeight.normal);

    final chip = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Versszak 1'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((chip.decoration as BoxDecoration?)?.color, scheme.primary);
  });

  testWidgets('flat look drops the card and reduces the tag to bold text', (
    tester,
  ) async {
    await pumpVerse(tester, LyricsTheme.flat(scheme));

    expect(tester.widget<Card>(find.byType(Card)).color, Colors.transparent);

    final tag = tester.widget<Text>(find.text('Versszak 1'));
    expect(tag.style!.color, scheme.onSurface);
    expect(tag.style!.fontWeight, FontWeight.bold);

    final chip = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Versszak 1'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((chip.decoration as BoxDecoration?)?.color, isNull);
  });
}
