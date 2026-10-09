import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/song_fields.dart';
import 'package:sofarhangolo/ui/song/widgets/song_details_helpers.dart';

Song _song() {
  return Song.fromBankApiJson({
    'uuid': 'song-1',
    'title': 'Song 1',
    'lyrics': '[V1]\n Hello Song',
    'composer': 'Composer A',
    'genre': ['Rock', 'Pop'],
    'orchestra': ['Big Band'],
  });
}

Future<void> _pumpDetails(
  WidgetTester tester,
  Song song, [
  Map<String, SongField>? registry,
]) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                Wrap(
                  children: getDetailsSummaryContent(song, context, registry),
                ),
                ...getDetailsContent(song, context, registry),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('summary and details render from the default registry', (
    tester,
  ) async {
    await _pumpDetails(tester, _song());

    // Summary chip: composer display value.
    expect(find.text('Composer A'), findsOneWidget);
    // Details row for a tag field (details use switched on for genre).
    expect(find.text('Stílus / műfaj'), findsOneWidget);
    expect(find.textContaining('Rock, Pop'), findsOneWidget);
    // Unknown field without a def does not render.
    expect(find.textContaining('orchestra'), findsNothing);
  });

  testWidgets('bank overlay fields join the summary and details', (
    tester,
  ) async {
    final registry = mergeSongFields(defaultSongFieldRegistry, {
      'orchestra': {
        'title': 'Zenekar',
        'type': 'list',
        'uses': ['details', 'summary'],
      },
    });

    await _pumpDetails(tester, _song(), registry);

    // Overlay field shows as a summary chip (icon falls back to the
    // help outline placeholder) and as a details row (whose text carries
    // selection break markers around the value).
    expect(find.textContaining('Big Band'), findsNWidgets(2));
    expect(find.text('Zenekar'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsAtLeastNWidgets(1));
  });

  testWidgets('overlay fields without a use stay hidden', (tester) async {
    final registry = mergeSongFields(defaultSongFieldRegistry, {
      'orchestra': {'type': 'list'},
    });

    await _pumpDetails(tester, _song(), registry);

    expect(find.text('Zenekar'), findsNothing);
    expect(find.text('Big Band'), findsNothing);
  });
}
