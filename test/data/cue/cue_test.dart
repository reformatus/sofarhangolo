import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/cue/slide.dart';

void main() {
  group('Cue', () {
    test('serializes from live slides after revival and mutation', () async {
      final cue = Cue(1, 'cue-uuid', 'Title', 'Description', 1, [
        {'slideType': 'unknown', 'uuid': 'slide-1', 'comment': null},
      ]);

      await cue.getRevivedSlides();

      cue.addSlide(
        UnknownTypeSlide(
          {'slideType': 'unknown', 'uuid': 'slide-2', 'comment': null},
          'slide-2',
          null,
        ),
      );

      final json = cue.toJson();
      final content = json['content'] as List;

      expect(content, hasLength(2));
      expect(content.map((entry) => entry['uuid']), ['slide-1', 'slide-2']);
    });

    test('can mutate raw serialized content before revival', () {
      final cue = Cue(1, 'cue-uuid', 'Title', 'Description', 1, []);

      cue.addSlide(
        UnknownTypeSlide(
          {'slideType': 'unknown', 'uuid': 'slide-1', 'comment': null},
          'slide-1',
          null,
        ),
      );

      expect(cue.content, hasLength(1));
      expect(cue.content.single['uuid'], 'slide-1');
    });
  });
}
