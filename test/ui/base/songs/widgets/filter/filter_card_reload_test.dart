import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:sofarhangolo/data/song/song_fields.dart';
import 'package:sofarhangolo/services/songs/facet.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/common/skeleton_chip_row.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/multiselect-tags/multiselect_filter_card.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/search/state.dart';

const _quick = Duration(milliseconds: 50);
const _slow = Duration(milliseconds: 400);

/// Reachable values follow the search string: none when empty, one otherwise.
Override _facetThatFollowsTheSearch(Duration answerIn) =>
    fieldFacetProvider.overrideWith((ref, field) async* {
      final search = ref.watch(searchStringStateProvider);
      await Future<void>.delayed(answerIn);
      yield search.isEmpty ? const <String>{} : const {'Rock'};
    });

SongField get _genre => defaultSongFieldRegistry['genre']!;

/// The card under test, bare - no page, no database.
Widget _cardUnderTest() => MaterialApp(
  home: Scaffold(
    body: MultiselectFilterCard(field: _genre, fieldPopulatedCount: 2),
  ),
);

void main() {
  late ProviderContainer container;

  void setSearch(String value) =>
      container.read(searchStringStateProvider.notifier).set(value);

  Future<void> pumpCard(
    WidgetTester tester, {
    Duration answerIn = _quick,
    String search = '',
  }) async {
    container = ProviderContainer(
      overrides: [_facetThatFollowsTheSearch(answerIn)],
    );
    addTearDown(container.dispose);
    if (search.isNotEmpty) setSearch(search);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _cardUnderTest()),
    );
    // Let the facet's own delay elapse first: pumpAndSettle only advances while
    // frames are scheduled, and waiting for a value schedules none.
    await tester.pump(answerIn + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
  }

  /// The chip row's target opacity, which is what the fade animates towards.
  double rowOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(MultiselectFilterCard),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('a card with nothing to offer stays, saying so', (tester) async {
    // An empty search reaches no value: the card keeps its place and its row
    // height, with the muted line instead of chips.
    await pumpCard(tester);
    expect(find.text('Nincs szűrhető dal.'), findsOneWidget);

    // A new query must not blank the row back to a skeleton while it loads.
    setSearch('rock');
    await tester.pump();
    expect(find.text('Nincs szűrhető dal.'), findsOneWidget);
    expect(find.byType(SkeletonChipRow), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Nincs szűrhető dal.'), findsNothing);
  });

  testWidgets('a card with chips keeps them while its facet reloads', (
    tester,
  ) async {
    await pumpCard(tester, search: 'rock');
    expect(find.text('Rock'), findsOneWidget);

    // The new query reaches nothing, but the card only swaps the chips for the
    // line once that result lands.
    setSearch('');
    await tester.pump();
    expect(find.text('Rock'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Nincs szűrhető dal.'), findsOneWidget);
    expect(find.text('Rock'), findsNothing);
  });

  testWidgets('a reload that finishes quickly never dims', (tester) async {
    await pumpCard(tester, search: 'rock');
    expect(find.text('Rock'), findsOneWidget);

    setSearch('more');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(rowOpacity(tester), 1, reason: 'still loading, but well inside it');

    await tester.pumpAndSettle();
    expect(rowOpacity(tester), 1);
  });

  testWidgets('a reload that drags dims after 200ms', (tester) async {
    await pumpCard(tester, answerIn: _slow, search: 'rock');
    expect(find.text('Rock'), findsOneWidget);

    setSearch('more');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(rowOpacity(tester), 1, reason: 'not yet worth dimming');

    await tester.pump(const Duration(milliseconds: 150));
    expect(rowOpacity(tester), 0.45);

    // Let the facet answer; the dim goes with the load.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(rowOpacity(tester), 1);
  });
}
