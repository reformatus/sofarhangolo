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

List<FractionalTranslation> inlineDrawerTranslations(WidgetTester tester) {
  return tester
      .widgetList<FractionalTranslation>(
        find.descendant(
          of: find.byType(AdaptivePage),
          matching: find.byType(FractionalTranslation),
        ),
      )
      .toList();
}

void main() {
  testWidgets('mobile shows the left preview and then hides inline drawers', (
    tester,
  ) async {
    await pumpAdaptivePage(tester, const Size(600, 900));

    expect(inlineDrawerTranslations(tester), hasLength(1));
    expect(
      inlineDrawerTranslations(tester).single.translation.dx,
      closeTo(0, 0.001),
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(inlineDrawerTranslations(tester), isEmpty);
  });

  testWidgets('tablet defaults to left open and right closed', (tester) async {
    await pumpAdaptivePage(tester, const Size(800, 900));

    final drawers = inlineDrawerTranslations(tester);

    expect(drawers, hasLength(2));
    expect(drawers.first.translation.dx, closeTo(0, 0.001));
    expect(drawers.last.translation.dx, closeTo(1, 0.001));
  });

  testWidgets('desktop defaults to both drawers open', (tester) async {
    await pumpAdaptivePage(tester, const Size(1200, 900));

    final drawers = inlineDrawerTranslations(tester);

    expect(drawers, hasLength(2));
    expect(drawers.first.translation.dx, closeTo(0, 0.001));
    expect(drawers.last.translation.dx, closeTo(0, 0.001));
  });

  testWidgets(
    'resizing to desktop keeps a user-opened tablet right drawer open',
    (tester) async {
      await pumpAdaptivePage(tester, const Size(800, 900));

      await tester.tap(find.byTooltip('Right drawer'));
      await tester.pumpAndSettle();

      expect(
        inlineDrawerTranslations(tester).last.translation.dx,
        closeTo(0, 0.001),
      );

      await resizeViewport(tester, const Size(1200, 900));

      expect(
        inlineDrawerTranslations(tester).last.translation.dx,
        closeTo(0, 0.001),
      );

      await tester.pump();

      expect(
        inlineDrawerTranslations(tester).last.translation.dx,
        closeTo(0, 0.001),
      );
    },
  );
}
