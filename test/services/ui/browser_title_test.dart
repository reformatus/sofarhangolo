import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/services/ui/browser_title.dart';

void main() {
  group('formatBrowserTabTitle', () {
    test('uses the app name by default', () {
      expect(formatBrowserTabTitle(), 'Sófár Hangoló');
    });

    test('prefixes contextual page titles', () {
      expect(
        formatBrowserTabTitle('Amazing Grace'),
        'Amazing Grace | Sófár Hangoló',
      );
    });

    test('ignores blank contextual titles', () {
      expect(formatBrowserTabTitle('   '), 'Sófár Hangoló');
    });
  });
}
