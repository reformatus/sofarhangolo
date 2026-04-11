import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/ui/cue/session/cue_session.dart';

void main() {
  group('CueSession', () {
    test('reads slides from the live cue object', () async {
      final cue = Cue(1, 'cue-uuid', 'Title', 'Description', 1, []);
      final slide = UnknownTypeSlide(
        {'slideType': 'unknown', 'uuid': 'slide-1', 'comment': null},
        'slide-1',
        null,
      );
      cue.addSlide(slide);
      await cue.getRevivedSlides();

      final session = CueSession(cue: cue, currentSlideUuid: 'slide-1');

      expect(session.slides, hasLength(1));
      expect(session.currentSlide?.uuid, 'slide-1');
      expect(session.slideCount, 1);
    });

    test('refreshed wrapper keeps the same cue instance', () async {
      final cue = Cue(1, 'cue-uuid', 'Old', 'Old description', 1, []);
      final slide = UnknownTypeSlide(
        {'slideType': 'unknown', 'uuid': 'slide-1', 'comment': null},
        'slide-1',
        null,
      );
      cue.addSlide(slide);
      await cue.getRevivedSlides();

      final session = CueSession(cue: cue, currentSlideUuid: 'slide-1');
      cue.updateMetadata(
        title: 'New',
        description: 'New description',
        cueVersion: 2,
      );

      final updated = session.refreshed();

      expect(updated.cue.title, 'New');
      expect(updated.cue.description, 'New description');
      expect(updated.cue.cueVersion, 2);
      expect(updated.cue, same(cue));
      expect(updated.currentSlideUuid, 'slide-1');
    });
  });
}
