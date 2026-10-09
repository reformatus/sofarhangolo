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

  group('Cue.reorderSlides', () {
    // ReorderableListView.onReorderItem already adjusts newIndex for the
    // item removed at oldIndex, so newIndex is the final index of the
    // moved slide (no extra -1 for downward moves).
    Cue cueWithSlides(List<String> uuids) {
      return Cue(1, 'cue-uuid', 'Title', 'Description', 1, [
        for (final uuid in uuids)
          {'slideType': 'unknown', 'uuid': uuid, 'comment': null},
      ]);
    }

    List<Object?> uuidsOf(Cue cue) => [
      for (final entry in cue.content) entry['uuid'],
    ];

    test('moves a slide down to its final index', () {
      final cue = cueWithSlides(['A', 'B', 'C', 'D']);

      cue.reorderSlides(0, 2); // A after C

      expect(uuidsOf(cue), ['B', 'C', 'A', 'D']);
    });

    test('moves a slide up to its final index', () {
      final cue = cueWithSlides(['A', 'B', 'C', 'D']);

      cue.reorderSlides(2, 0); // C before A

      expect(uuidsOf(cue), ['C', 'A', 'B', 'D']);
    });

    test('moves a slide to the end', () {
      final cue = cueWithSlides(['A', 'B', 'C', 'D']);

      cue.reorderSlides(0, 3); // A after D

      expect(uuidsOf(cue), ['B', 'C', 'D', 'A']);
    });

    test('applies the same order to revived slides', () async {
      final cue = cueWithSlides(['A', 'B', 'C', 'D']);
      await cue.getRevivedSlides();

      cue.reorderSlides(0, 2); // A after C

      expect(uuidsOf(cue), ['B', 'C', 'A', 'D']);
    });
  });
}
