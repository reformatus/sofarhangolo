import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:sofarhangolo/data/song/song_fields.dart';
import 'package:sofarhangolo/services/songs/facet.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/common/base_filter_card.dart';
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

  testWidgets('a hidden card stays hidden while its facet reloads', (
    tester,
  ) async {
    // An empty search reaches no value, so the card settles hidden.
    await pumpCard(tester);
    expect(find.byType(BaseFilterCard), findsNothing);

    // The reload must not bring the card back before the new value lands.
    setSearch('rock');
    await tester.pump();
    expect(
      find.byType(BaseFilterCard),
      findsNothing,
      reason: 'a hidden card must not flash back while its facet is loading',
    );

    await tester.pumpAndSettle();
    expect(find.byType(BaseFilterCard), findsOneWidget);
  });

  testWidgets('a shown card keeps its chips while its facet reloads', (
    tester,
  ) async {
    setSearch('rock');
    await pumpCard(tester);
    expect(find.text('Rock'), findsOneWidget);

    // The card only disappears once the empty result lands; until then it keeps
    // fading its chips.
    setSearch('');
    await tester.pump();
    expect(
      find.text('Rock'),
      findsOneWidget,
      reason: 'the previous chips stay while the new query loads',
    );

    await tester.pumpAndSettle();
    expect(find.byType(BaseFilterCard), findsNothing);
  });
}
