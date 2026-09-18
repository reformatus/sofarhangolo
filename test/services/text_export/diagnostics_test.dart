import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/services/text_export/diagnostics.dart';

void main() {
  group('capStackLines', () {
    test('returns short stacks unchanged', () {
      expect(capStackLines('line 1\nline 2'), 'line 1\nline 2');
    });

    test('returns empty string for null or empty stacks', () {
      expect(capStackLines(null), isEmpty);
      expect(capStackLines(''), isEmpty);
    });

    test('caps long stacks and notes the omitted line count', () {
      final stack = List.generate(25, (i) => 'line ${i + 1}').join('\n');
      final capped = capStackLines(stack, maxLines: 20);

      expect(capped.split('\n'), hasLength(21));
      expect(capped, startsWith('line 1'));
      expect(capped, contains('… (5 további sor)'));
    });
  });

  group('formatDiagnostics', () {
    test('joins the provided parts with blank lines', () {
      final text = formatDiagnostics(
        title: 'Hiba',
        message: 'Nem sikerült betölteni.',
        stack: 'stack line',
      );

      expect(text, 'Hiba\n\nNem sikerült betölteni.\n\nstack line');
    });

    test('skips empty parts', () {
      expect(formatDiagnostics(title: 'Hiba'), 'Hiba');
      expect(formatDiagnostics(), isEmpty);
    });
  });

  group('formatLogEntry', () {
    test('includes severity, timestamp, message, error and capped stack', () {
      final entry = formatLogEntry(
        level: 'SEVERE',
        time: DateTime(2026, 9, 18, 14, 5),
        message: 'Nem sikerült betölteni a dalt.',
        error: StateError('boom'),
        stackTrace: StackTrace.current,
      );

      expect(
        entry,
        startsWith('[SEVERE 2026-09-18 14:05] Nem sikerült betölteni a dalt.'),
      );
      expect(entry, contains('Bad state: boom'));
      final stackLineCount = entry.split('\n\n').last.split('\n').length;
      expect(stackLineCount, lessThanOrEqualTo(defaultMaxStackLines));
    });

    test('omits missing error and stack', () {
      final entry = formatLogEntry(
        level: 'INFO',
        time: DateTime(2026, 1, 2, 3, 4),
        message: 'Minden rendben.',
      );

      expect(entry, '[INFO 2026-01-02 03:04] Minden rendben.');
    });
  });
}
