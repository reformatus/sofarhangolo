import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/ui/common/adaptive_page/page.dart';

Future<void> pumpAdaptivePage(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(accessibleNavigation: false),
          child: child!,
        );
      },
      home: const AdaptivePage(
        title: 'Cue editor',
        body: SizedBox.expand(),
        leftDrawer: ColoredBox(color: Colors.red, child: SizedBox.expand()),
        leftDrawerTooltip: 'Left drawer',
        rightDrawer: ColoredBox(color: Colors.blue, child: SizedBox.expand()),
        rightDrawerTooltip: 'Right drawer',
      ),
    ),
  );
  await tester.pump();
}

Future<void> resizeViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
}

/// The FractionalTranslation wrappers of the *inline* drawers only.
///
/// A default-open drawer is wrapped by our own [FractionalTranslation] so it
/// can collapse/expand inline. The Scaffold overlay drawer instead lives in a
/// [SlideTransition], which happens to build a FractionalTranslation too, so we
/// scope the search to ancestors of the inline [Drawer]s. Inline drawers are
/// the only ones using a rounded [RoundedRectangleBorder] shape.
List<FractionalTranslation> inlineDrawerTranslations(WidgetTester tester) {
  final inlineDrawers = find.byWidgetPredicate(
    (widget) => widget is Drawer && widget.shape is RoundedRectangleBorder,
  );
  return tester
      .widgetList<FractionalTranslation>(
        find.ancestor(
          of: inlineDrawers,
          matching: find.descendant(
            of: find.byType(AdaptivePage),
            matching: find.byType(FractionalTranslation),
          ),
        ),
      )
      .toList();
}

Finder drawerContent(Color color) {
  return find.byWidgetPredicate(
    (widget) => widget is ColoredBox && widget.color == color,
  );
}

void main() {
  testWidgets('mobile hides both drawers inline and opens them as overlays', (
    tester,
  ) async {
    await pumpAdaptivePage(tester, const Size(600, 900));

    // Nothing is rendered inline and neither drawer content is on screen.
    expect(inlineDrawerTranslations(tester), isEmpty);
    expect(drawerContent(Colors.red), findsNothing);
    expect(drawerContent(Colors.blue), findsNothing);

    // The left toggle opens the Scaffold overlay drawer instead.
    await tester.tap(find.byTooltip('Left drawer'));
    await tester.pumpAndSettle();

    expect(drawerContent(Colors.red), findsOneWidget);
    expect(inlineDrawerTranslations(tester), isEmpty);
  });

  testWidgets('tablet keeps only the left drawer inline', (tester) async {
    await pumpAdaptivePage(tester, const Size(800, 900));

    final drawers = inlineDrawerTranslations(tester);

    expect(drawers, hasLength(1));
    expect(drawers.single.translation.dx, closeTo(0, 0.001));
    expect(drawerContent(Colors.red), findsOneWidget);
    // The right drawer is hidden, so its content is not built at all.
    expect(drawerContent(Colors.blue), findsNothing);
  });

  testWidgets('tablet right drawer opens as an overlay, never inline', (
    tester,
  ) async {
    await pumpAdaptivePage(tester, const Size(800, 900));

    expect(inlineDrawerTranslations(tester), hasLength(1));
    expect(drawerContent(Colors.blue), findsNothing);

    await tester.tap(find.byTooltip('Right drawer'));
    await tester.pumpAndSettle();

    // The content is now visible, but no inline panel was created for it.
    expect(drawerContent(Colors.blue), findsOneWidget);
    expect(inlineDrawerTranslations(tester), hasLength(1));
  });

  testWidgets('desktop defaults to both drawers inline and open', (
    tester,
  ) async {
    await pumpAdaptivePage(tester, const Size(1200, 900));

    final drawers = inlineDrawerTranslations(tester);

    expect(drawers, hasLength(2));
    expect(drawers.first.translation.dx, closeTo(0, 0.001));
    expect(drawers.last.translation.dx, closeTo(0, 0.001));
    expect(drawerContent(Colors.red), findsOneWidget);
    expect(drawerContent(Colors.blue), findsOneWidget);
  });

  testWidgets(
    'widening to desktop brings an overlay-opened right drawer inline',
    (tester) async {
      await pumpAdaptivePage(tester, const Size(800, 900));

      await tester.tap(find.byTooltip('Right drawer'));
      await tester.pumpAndSettle();
      expect(drawerContent(Colors.blue), findsOneWidget);
      expect(inlineDrawerTranslations(tester), hasLength(1));

      // On desktop the right drawer becomes default-open, so it is rendered
      // inline (and the overlay is torn down).
      await resizeViewport(tester, const Size(1200, 900));
      await tester.pumpAndSettle();

      final drawers = inlineDrawerTranslations(tester);
      expect(drawers, hasLength(2));
      expect(drawers.last.translation.dx, closeTo(0, 0.001));
      expect(drawerContent(Colors.blue), findsOneWidget);
    },
  );

  testWidgets('narrowing keeps an open overlay drawer working', (tester) async {
    await pumpAdaptivePage(tester, const Size(800, 900));

    await tester.tap(find.byTooltip('Right drawer'));
    await tester.pumpAndSettle();

    await resizeViewport(tester, const Size(600, 900));
    await tester.pumpAndSettle();

    // Still an overlay on mobile: open and never rendered inline.
    expect(drawerContent(Colors.blue), findsOneWidget);
    expect(inlineDrawerTranslations(tester), isEmpty);
  });
}
