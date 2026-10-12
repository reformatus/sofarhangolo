import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/ui/common/notice/card.dart';

Future<void> _pump(
  WidgetTester tester,
  LNoticeCard card, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(8), child: card),
      ),
    ),
  );
}

LNoticeCard _card({
  required LNoticeType type,
  List<Widget> actions = const [],
}) {
  return LNoticeCard(
    type: type,
    icon: Icons.notifications_none,
    title: 'Cím',
    message: 'Üzenet',
    actions: actions,
  );
}

void main() {
  testWidgets('info boxes take the theme accent, warnings/errors stay fixed', (
    tester,
  ) async {
    final theme = ThemeData.from(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
      useMaterial3: true,
    );
    final accent = theme.colorScheme.primary;

    for (final entry in {
      LNoticeType.info: accent,
      LNoticeType.warning: Colors.orange,
      LNoticeType.error: Colors.red,
    }.entries) {
      await _pump(tester, _card(type: entry.key), theme: theme);
      final icon = tester.widget<Icon>(find.byIcon(Icons.notifications_none));
      expect(icon.color, entry.value.withAlpha(200));
    }
  });

  testWidgets('actions live inside the box, spanning its width', (
    tester,
  ) async {
    await _pump(
      tester,
      _card(
        type: LNoticeType.info,
        actions: [
          OutlinedButton(
            onPressed: () {},
            child: const Text('Művelet'),
          ),
        ],
      ),
    );

    final card = tester.getRect(find.byType(Card));
    final button = tester.getRect(find.byType(OutlinedButton));

    // The button is part of the box, not a loose control under it…
    expect(card.top, lessThan(button.top));
    expect(card.bottom, greaterThan(button.bottom));
    // …and it fills the box's inner width.
    expect(button.left, greaterThan(card.left));
    expect(button.right, lessThan(card.right));
    expect(button.width, card.width - 32);
  });
}
