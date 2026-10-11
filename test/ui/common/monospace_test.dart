import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/ui/common/monospace.dart';

void main() {
  test('monospace style prefers a concrete family with fallbacks', () {
    expect(monospaceTextStyle.fontFamily, 'Courier New');
    expect(monospaceTextStyle.fontFamilyFallback, isNotEmpty);
    expect(monospaceTextStyle.fontFamilyFallback, contains('monospace'));
  });
}
