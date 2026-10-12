import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:sofarhangolo/data/song/song_fields.dart';
import 'package:sofarhangolo/services/songs/facet.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/common/skeleton_chip_row.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/multiselect-tags/multiselect_filter_card.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/search/state.dart';

/// How long the fake facet takes to answer, so a test can hold it reloading.
const _reload = Duration(milliseconds: 50);

/// Reachable values follow the search string: none when empty, one otherwise.
Override _facetThatFollowsTheSearch() =>
    fieldFacetProvider.overrideWith((ref, field) async* {
      final search = ref.watch(searchStringStateProvider);
      await Future<void>.delayed(_reload);
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

  setUp(() {
    container = ProviderContainer(overrides: [_facetThatFollowsTheSearch()]);
    addTearDown(container.dispose);
  });

  void setSearch(String value) =>
      container.read(searchStringStateProvider.notifier).set(value);

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _cardUnderTest()),
    );
    await tester.pumpAndSettle();
  }

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
    setSearch('rock');
    await pumpCard(tester);
    expect(find.text('Rock'), findsOneWidget);

    // The new query reaches nothing, but the card only swaps the chips for the
    // line once that result lands - it fades what it has meanwhile.
    setSearch('');
    await tester.pump();
    expect(find.text('Rock'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Nincs szűrhető dal.'), findsOneWidget);
    expect(find.text('Rock'), findsNothing);
  });
}
