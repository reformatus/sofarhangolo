import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/services/cue/import_from_link.dart';

void main() {
  group('CueImportResult.getNavigationPath', () {
    test('returns an absolute cue editor route', () {
      final cue = Cue(1, 'cue-123', 'Cue', '', currentCueVersion, const []);

      final route = CueImportResult(cue, null).getNavigationPath();

      expect(route, '/cue/cue-123/edit');
    });

    test('includes the initial slide as a query parameter', () {
      final cue = Cue(1, 'cue-123', 'Cue', '', currentCueVersion, const []);

      final route = CueImportResult(cue, 'slide-1').getNavigationPath();

      expect(route, '/cue/cue-123/edit?slide=slide-1');
    });
  });
}
