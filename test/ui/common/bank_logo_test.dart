import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/ui/common/bank_logo.dart';

// 1×1 transparent PNG.
final Uint8List _pngBytes = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('renders the bank image when there is one', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Center(child: BankLogo(image: _pngBytes))),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('falls back to the default bank icon without an image', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: BankLogo())),
    );

    expect(find.byType(Image), findsNothing);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.library_music);
  });

  testWidgets('accepts a custom fallback icon and color', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: BankLogo(icon: Icons.home, color: Color(0xFF123456)),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.home);
    expect(icon.color, const Color(0xFF123456));
  });

  testWidgets('occupies its size square either way', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: BankLogo(size: 30))),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(BankLogo)), const Size(30, 30));
  });
}
