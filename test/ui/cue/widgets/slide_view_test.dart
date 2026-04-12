import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/ui/cue/widgets/slide_view.dart';
import 'package:sofarhangolo/ui/song/state.dart';

import '../../../harness/cue_widget_harness.dart';
import '../../../harness/test_harness.dart';

void main() {
  group('SlideView cue interactions', () {
    late LyricDatabase testDb;
    late TestHarness harness;

    setUp(() async {
      testDb = createTestDatabase();
      db = testDb;
      await db.customStatement('PRAGMA foreign_keys = OFF');
      harness = TestHarness();
    });

    tearDown(() async {
      harness.dispose();
      await testDb.close();
    });

    testWidgets(
      'successive swipes update the rest of the cue UI without rebuilding the active slide tree',
      (tester) async {
        final cue = await insertCueHarnessCue(
          cueUuid: 'cue-swipe',
          fixtures: const [
            CueSongFixture(
              songUuid: 'song-1',
              slideUuid: 'slide-1',
              title: 'Song 1',
              lyrics: '[V1]\n Alpha line',
            ),
            CueSongFixture(
              songUuid: 'song-2',
              slideUuid: 'slide-2',
              title: 'Song 2',
              lyrics: '[V1]\n Beta line',
            ),
            CueSongFixture(
              songUuid: 'song-3',
              slideUuid: 'slide-3',
              title: 'Song 3',
              lyrics: '[V1]\n Gamma line',
            ),
          ],
        );

        final cueHarness = await pumpCueWidgetHarness(
          tester,
          testHarness: harness,
          cueUuid: cue.uuid,
        );

        expect(find.text('current:slide-1'), findsOneWidget);
        expect(find.text('Alpha line'), findsOneWidget);

        final slideViewport = find.byType(SlideView);
        final pageWidth = tester.getSize(slideViewport).width;

        await tester.drag(slideViewport, Offset(-(pageWidth * 0.6), 0));
        await tester.pumpAndSettle();

        expect(cueHarness.session.currentSlideUuid, 'slide-2');
        expect(find.text('Beta line'), findsOneWidget);

        await tester.drag(slideViewport, Offset(-(pageWidth * 0.6), 0));
        await tester.pumpAndSettle();

        expect(cueHarness.session.currentSlideUuid, 'slide-3');
        expect(find.text('Gamma line'), findsOneWidget);
      },
    );

    testWidgets(
      'partial horizontal drag previews the adjacent slide before release',
      (tester) async {
        final cue = await insertCueHarnessCue(
          cueUuid: 'cue-partial-preview',
          fixtures: const [
            CueSongFixture(
              songUuid: 'song-1',
              slideUuid: 'slide-1',
              title: 'Song 1',
              lyrics: '[V1]\n Alpha line',
            ),
            CueSongFixture(
              songUuid: 'song-2',
              slideUuid: 'slide-2',
              title: 'Song 2',
              lyrics: '[V1]\n Beta line',
            ),
          ],
        );

        final cueHarness = await pumpCueWidgetHarness(
          tester,
          testHarness: harness,
          cueUuid: cue.uuid,
        );

        final slideViewport = find.byType(SlideView);
        final pageWidth = tester.getSize(slideViewport).width;
        final gesture = await tester.createGesture();

        await gesture.down(tester.getCenter(slideViewport));
        await gesture.moveBy(Offset(-(pageWidth * 0.3), 0));
        await tester.pump();

        expect(cueHarness.session.currentSlideUuid, 'slide-1');
        expect(find.text('Alpha line'), findsOneWidget);
        expect(find.text('Beta line'), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();

        expect(cueHarness.session.currentSlideUuid, 'slide-1');
      },
    );

    testWidgets('dragging reuses retained slide trees after first warm-up', (
      tester,
    ) async {
      final buildCounts = <String, int>{};
      debugSlideViewBuildLogger = (slideUuid) {
        buildCounts.update(slideUuid, (count) => count + 1, ifAbsent: () => 1);
      };
      addTearDown(() {
        debugSlideViewBuildLogger = null;
      });

      final cue = await insertCueHarnessCue(
        cueUuid: 'cue-build-cache',
        fixtures: const [
          CueSongFixture(
            songUuid: 'song-1',
            slideUuid: 'slide-1',
            title: 'Song 1',
            lyrics: '[V1]\n Alpha line',
          ),
          CueSongFixture(
            songUuid: 'song-2',
            slideUuid: 'slide-2',
            title: 'Song 2',
            lyrics: '[V1]\n Beta line',
          ),
        ],
      );

      await pumpCueWidgetHarness(
        tester,
        testHarness: harness,
        cueUuid: cue.uuid,
      );

      final slideViewport = find.byType(SlideView);
      final pageWidth = tester.getSize(slideViewport).width;
      final gesture = await tester.createGesture();

      final initialCurrentBuilds = buildCounts['slide-1'] ?? 0;
      expect(initialCurrentBuilds, greaterThan(0));
      expect(buildCounts['slide-2'] ?? 0, 0);

      await gesture.down(tester.getCenter(slideViewport));
      await gesture.moveBy(Offset(-(pageWidth * 0.25), 0));
      await tester.pump();

      final warmedCurrentBuilds = buildCounts['slide-1'] ?? 0;
      final warmedTargetBuilds = buildCounts['slide-2'] ?? 0;

      expect(warmedCurrentBuilds, greaterThanOrEqualTo(initialCurrentBuilds));
      expect(warmedTargetBuilds, greaterThan(0));

      final stabilizedCurrentBuilds = buildCounts['slide-1'] ?? 0;
      final stabilizedTargetBuilds = buildCounts['slide-2'] ?? 0;

      await gesture.moveBy(Offset(-(pageWidth * 0.2), 0));
      await tester.pump();
      await gesture.moveBy(Offset(-(pageWidth * 0.1), 0));
      await tester.pump();

      expect(buildCounts['slide-1'], stabilizedCurrentBuilds);
      expect(buildCounts['slide-2'], stabilizedTargetBuilds);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'full-width drag commits once and ignores further movement in the same gesture',
      (tester) async {
        final cue = await insertCueHarnessCue(
          cueUuid: 'cue-drag-lock',
          fixtures: const [
            CueSongFixture(
              songUuid: 'song-1',
              slideUuid: 'slide-1',
              title: 'Song 1',
              lyrics: '[V1]\n Alpha line',
            ),
            CueSongFixture(
              songUuid: 'song-2',
              slideUuid: 'slide-2',
              title: 'Song 2',
              lyrics: '[V1]\n Beta line',
            ),
            CueSongFixture(
              songUuid: 'song-3',
              slideUuid: 'slide-3',
              title: 'Song 3',
              lyrics: '[V1]\n Gamma line',
            ),
          ],
        );

        final cueHarness = await pumpCueWidgetHarness(
          tester,
          testHarness: harness,
          cueUuid: cue.uuid,
        );

        final slideViewport = find.byType(SlideView);
        final pageWidth = tester.getSize(slideViewport).width;
        final gesture = await tester.createGesture();

        await gesture.down(tester.getCenter(slideViewport));
        await gesture.moveBy(Offset(-(pageWidth * 1.05), 0));
        await tester.pump();

        expect(cueHarness.session.currentSlideUuid, 'slide-2');
        expect(find.text('current:slide-2'), findsOneWidget);

        await gesture.moveBy(Offset(-(pageWidth * 0.8), 0));
        await tester.pump();

        expect(cueHarness.session.currentSlideUuid, 'slide-2');
        expect(find.text('current:slide-2'), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();

        expect(cueHarness.session.currentSlideUuid, 'slide-2');
        expect(find.text('Beta line'), findsOneWidget);
      },
    );

    testWidgets(
      'changing drag direction can cross through zero and preview the opposite neighbor',
      (tester) async {
        final cue = await insertCueHarnessCue(
          cueUuid: 'cue-direction-reversal',
          fixtures: const [
            CueSongFixture(
              songUuid: 'song-1',
              slideUuid: 'slide-1',
              title: 'Song 1',
              lyrics: '[V1]\n Alpha line',
            ),
            CueSongFixture(
              songUuid: 'song-2',
              slideUuid: 'slide-2',
              title: 'Song 2',
              lyrics: '[V1]\n Beta line',
            ),
            CueSongFixture(
              songUuid: 'song-3',
              slideUuid: 'slide-3',
              title: 'Song 3',
              lyrics: '[V1]\n Gamma line',
            ),
          ],
        );

        final cueHarness = await pumpCueWidgetHarness(
          tester,
          testHarness: harness,
          cueUuid: cue.uuid,
          initialSlideUuid: 'slide-2',
        );

        final slideViewport = find.byType(SlideView);
        final pageWidth = tester.getSize(slideViewport).width;
        final gesture = await tester.createGesture();
        await gesture.down(tester.getCenter(slideViewport));
        await gesture.moveBy(Offset(-(pageWidth * 0.3), 0));
        await tester.pump();

        expect(find.text('Gamma line'), findsOneWidget);
        expect(find.text('Alpha line'), findsNothing);
        expect(cueHarness.session.currentSlideUuid, 'slide-2');

        await gesture.moveBy(Offset(pageWidth * 0.2, 0));
        await tester.pump();

        expect(find.text('Gamma line'), findsOneWidget);
        expect(find.text('Alpha line'), findsNothing);
        expect(cueHarness.session.currentSlideUuid, 'slide-2');

        await gesture.moveBy(Offset(pageWidth * 0.25, 0));
        await tester.pump();

        expect(find.text('Alpha line'), findsOneWidget);
        expect(find.text('Gamma line'), findsNothing);
        expect(cueHarness.session.currentSlideUuid, 'slide-2');

        await gesture.up();
        await tester.pumpAndSettle();

        expect(cueHarness.session.currentSlideUuid, 'slide-2');
      },
    );

    testWidgets(
      'vertical drags stay on the current slide so cue lyrics can scroll',
      (tester) async {
        final cue = await insertCueHarnessCue(
          cueUuid: 'cue-vertical-scroll',
          fixtures: const [
            CueSongFixture(
              songUuid: 'song-1',
              slideUuid: 'slide-1',
              title: 'Song 1',
              lyrics:
                  '[V1]\n Line 01\n Line 02\n Line 03\n Line 04\n Line 05\n'
                  'Line 06\n Line 07\n Line 08\n Line 09\n Line 10\n'
                  'Line 11\n Line 12\n Line 13\n Line 14\n Line 15\n'
                  'Line 16\n Line 17\n Line 18\n Line 19\n Line 20',
            ),
            CueSongFixture(
              songUuid: 'song-2',
              slideUuid: 'slide-2',
              title: 'Song 2',
              lyrics: '[V1]\n Second slide line',
            ),
          ],
        );

        final cueHarness = await pumpCueWidgetHarness(
          tester,
          testHarness: harness,
          cueUuid: cue.uuid,
        );

        await tester.drag(find.byType(SlideView), const Offset(0, -250));
        await tester.pumpAndSettle();

        expect(cueHarness.session.currentSlideUuid, 'slide-1');
        expect(find.text('current:slide-1'), findsOneWidget);
      },
    );

    testWidgets('two-finger gestures do not trigger cue slide navigation', (
      tester,
    ) async {
      configureCueHarnessSvgResponse(harness, svgLabel: 'Cue SVG');

      final cue = await insertCueHarnessCue(
        cueUuid: 'cue-multitouch',
        fixtures: const [
          CueSongFixture(
            songUuid: 'song-1',
            slideUuid: 'slide-1',
            title: 'Song 1',
            lyrics: '[V1]\n Alpha line',
            viewType: SongViewType.svg,
            hasSvg: true,
          ),
          CueSongFixture(
            songUuid: 'song-2',
            slideUuid: 'slide-2',
            title: 'Song 2',
            lyrics: '[V1]\n Beta line',
            viewType: SongViewType.svg,
            hasSvg: true,
          ),
        ],
      );

      final cueHarness = await pumpCueWidgetHarness(
        tester,
        testHarness: harness,
        cueUuid: cue.uuid,
      );

      final center = tester.getCenter(find.byType(SlideView));
      final firstFinger = await tester.createGesture();
      final secondFinger = await tester.createGesture(pointer: 2);

      await firstFinger.down(center - const Offset(30, 0));
      await secondFinger.down(center + const Offset(30, 0));
      await tester.pump();

      await firstFinger.moveBy(const Offset(-120, 0));
      await secondFinger.moveBy(const Offset(-120, 0));
      await tester.pump();

      await firstFinger.up();
      await secondFinger.up();
      await tester.pumpAndSettle();

      expect(cueHarness.session.currentSlideUuid, 'slide-1');
      expect(find.text('current:slide-1'), findsOneWidget);
    });

    testWidgets('outside trigger animates when advancing', (tester) async {
      ({
        String? settledSlideUuid,
        String? targetSlideUuid,
        double transitionProgress,
        int transitionDirection,
      })?
      lastTransitionState;
      debugSlideViewTransitionLogger =
          ({
            required settledSlideUuid,
            required targetSlideUuid,
            required transitionProgress,
            required transitionDirection,
          }) {
            lastTransitionState = (
              settledSlideUuid: settledSlideUuid,
              targetSlideUuid: targetSlideUuid,
              transitionProgress: transitionProgress,
              transitionDirection: transitionDirection,
            );
          };
      addTearDown(() {
        debugSlideViewTransitionLogger = null;
      });

      final cue = await insertCueHarnessCue(
        cueUuid: 'cue-forward-outside-trigger',
        fixtures: const [
          CueSongFixture(
            songUuid: 'song-1',
            slideUuid: 'slide-1',
            title: 'Song 1',
            lyrics: '[V1]\n Alpha line',
          ),
          CueSongFixture(
            songUuid: 'song-2',
            slideUuid: 'slide-2',
            title: 'Song 2',
            lyrics: '[V1]\n Beta line',
          ),
        ],
      );

      final cueHarness = await pumpCueWidgetHarness(
        tester,
        testHarness: harness,
        cueUuid: cue.uuid,
      );

      cueHarness.jumpToSlide('slide-2');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(lastTransitionState?.targetSlideUuid, 'slide-2');
      expect(lastTransitionState?.transitionDirection, 1);
      expect(lastTransitionState!.transitionProgress, lessThan(0));
      expect(lastTransitionState!.transitionProgress, greaterThan(-1));

      await tester.pumpAndSettle();

      expect(cueHarness.session.currentSlideUuid, 'slide-2');
    });

    testWidgets('releasing an advancing drag continues the forward animation', (
      tester,
    ) async {
      ({
        String? settledSlideUuid,
        String? targetSlideUuid,
        double transitionProgress,
        int transitionDirection,
      })?
      lastTransitionState;
      debugSlideViewTransitionLogger =
          ({
            required settledSlideUuid,
            required targetSlideUuid,
            required transitionProgress,
            required transitionDirection,
          }) {
            lastTransitionState = (
              settledSlideUuid: settledSlideUuid,
              targetSlideUuid: targetSlideUuid,
              transitionProgress: transitionProgress,
              transitionDirection: transitionDirection,
            );
          };
      addTearDown(() {
        debugSlideViewTransitionLogger = null;
      });

      final cue = await insertCueHarnessCue(
        cueUuid: 'cue-forward-release',
        fixtures: const [
          CueSongFixture(
            songUuid: 'song-1',
            slideUuid: 'slide-1',
            title: 'Song 1',
            lyrics: '[V1]\n Alpha line',
          ),
          CueSongFixture(
            songUuid: 'song-2',
            slideUuid: 'slide-2',
            title: 'Song 2',
            lyrics: '[V1]\n Beta line',
          ),
        ],
      );

      final cueHarness = await pumpCueWidgetHarness(
        tester,
        testHarness: harness,
        cueUuid: cue.uuid,
      );

      final slideViewport = find.byType(SlideView);
      final pageWidth = tester.getSize(slideViewport).width;
      final gesture = await tester.createGesture();

      await gesture.down(tester.getCenter(slideViewport));
      await gesture.moveBy(Offset(-(pageWidth * 0.6), 0));
      await tester.pump();

      final progressBeforeRelease = lastTransitionState!.transitionProgress;
      expect(progressBeforeRelease, lessThan(0));

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(lastTransitionState?.targetSlideUuid, 'slide-2');
      expect(lastTransitionState?.transitionDirection, 1);
      expect(
        lastTransitionState!.transitionProgress,
        lessThan(progressBeforeRelease),
      );

      await tester.pumpAndSettle();

      expect(cueHarness.session.currentSlideUuid, 'slide-2');
    });

    testWidgets(
      'outside jump buttons move the active slide without rebuilding the slide tree',
      (tester) async {
        final cue = await insertCueHarnessCue(
          cueUuid: 'cue-jump',
          fixtures: const [
            CueSongFixture(
              songUuid: 'song-1',
              slideUuid: 'slide-1',
              title: 'Song 1',
              lyrics: '[V1]\n Alpha line',
            ),
            CueSongFixture(
              songUuid: 'song-2',
              slideUuid: 'slide-2',
              title: 'Song 2',
              lyrics: '[V1]\n Beta line',
            ),
            CueSongFixture(
              songUuid: 'song-3',
              slideUuid: 'slide-3',
              title: 'Song 3',
              lyrics: '[V1]\n Gamma line',
            ),
          ],
        );

        final cueHarness = await pumpCueWidgetHarness(
          tester,
          testHarness: harness,
          cueUuid: cue.uuid,
        );

        cueHarness.jumpToSlide('slide-3');
        await tester.pumpAndSettle();

        expect(cueHarness.session.currentSlideUuid, 'slide-3');
        expect(find.text('Gamma line'), findsOneWidget);
      },
    );

    testWidgets(
      'button navigation changes the active slide without rebuilding the slide tree',
      (tester) async {
        final cue = await insertCueHarnessCue(
          cueUuid: 'cue-buttons',
          fixtures: const [
            CueSongFixture(
              songUuid: 'song-1',
              slideUuid: 'slide-1',
              title: 'Song 1',
              lyrics: '[V1]\n Alpha line',
            ),
            CueSongFixture(
              songUuid: 'song-2',
              slideUuid: 'slide-2',
              title: 'Song 2',
              lyrics: '[V1]\n Beta line',
            ),
          ],
        );

        final cueHarness = await pumpCueWidgetHarness(
          tester,
          testHarness: harness,
          cueUuid: cue.uuid,
        );

        await tester.tap(find.byKey(cueHarnessNextButtonKey));
        await tester.pumpAndSettle();

        expect(cueHarness.session.currentSlideUuid, 'slide-2');
        expect(find.text('Beta line'), findsOneWidget);
      },
    );

    testWidgets(
      'rapid button navigation during settle does not crash the active slide view',
      (tester) async {
        final cue = await insertCueHarnessCue(
          cueUuid: 'cue-rapid-buttons',
          fixtures: const [
            CueSongFixture(
              songUuid: 'song-1',
              slideUuid: 'slide-1',
              title: 'Song 1',
              lyrics: '[V1]\n Alpha line',
            ),
            CueSongFixture(
              songUuid: 'song-2',
              slideUuid: 'slide-2',
              title: 'Song 2',
              lyrics: '[V1]\n Beta line',
            ),
            CueSongFixture(
              songUuid: 'song-3',
              slideUuid: 'slide-3',
              title: 'Song 3',
              lyrics: '[V1]\n Gamma line',
            ),
          ],
        );

        final cueHarness = await pumpCueWidgetHarness(
          tester,
          testHarness: harness,
          cueUuid: cue.uuid,
        );

        await tester.tap(find.byKey(cueHarnessNextButtonKey));
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.byKey(cueHarnessNextButtonKey));
        await tester.pump();

        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();

        expect(cueHarness.session.currentSlideUuid, 'slide-3');
        expect(find.text('Gamma line'), findsOneWidget);
      },
    );

    testWidgets(
      'view chooser mutates the current cue slide without rebuilding the slide tree',
      (tester) async {
        configureCueHarnessSvgResponse(harness, svgLabel: 'Cue SVG');

        final cue = await insertCueHarnessCue(
          cueUuid: 'cue-view-type',
          fixtures: const [
            CueSongFixture(
              songUuid: 'song-1',
              slideUuid: 'slide-1',
              title: 'Chord Song',
              lyrics: '[V1]\n. C\n Chord line',
              viewType: SongViewType.chords,
              hasSvg: true,
            ),
          ],
        );

        final cueHarness = await pumpCueWidgetHarness(
          tester,
          testHarness: harness,
          cueUuid: cue.uuid,
        );

        expect(find.text('TRANSZPONÁLÁS'), findsOneWidget);
        expect(cueHarness.currentSongSlide.viewType, SongViewType.chords);

        await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kotta').last);
        await tester.pumpAndSettle();

        expect(cueHarness.currentSongSlide.viewType, SongViewType.svg);
        expect(find.text('TRANSZPONÁLÁS'), findsNothing);
      },
    );

    testWidgets(
      'transpose controls mutate the current cue slide without rebuilding the slide tree',
      (tester) async {
        final cue = await insertCueHarnessCue(
          cueUuid: 'cue-transpose',
          fixtures: const [
            CueSongFixture(
              songUuid: 'song-1',
              slideUuid: 'slide-1',
              title: 'Chord Song',
              lyrics: '[V1]\n. C\n Chord line',
              viewType: SongViewType.chords,
            ),
          ],
        );

        final cueHarness = await pumpCueWidgetHarness(
          tester,
          testHarness: harness,
          cueUuid: cue.uuid,
        );

        expect(cueHarness.currentSongSlide.transpose, isNull);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        expect(cueHarness.currentSongSlide.transpose?.capo, 1);
        expect(find.text('Capo: 1'), findsOneWidget);
      },
    );

    testWidgets('structural slide list changes refresh the slide deck once', (
      tester,
    ) async {
      final cue = await insertCueHarnessCue(
        cueUuid: 'cue-structure',
        fixtures: const [
          CueSongFixture(
            songUuid: 'song-1',
            slideUuid: 'slide-1',
            title: 'Song 1',
            lyrics: '[V1]\n Alpha line',
          ),
        ],
      );

      final cueHarness = await pumpCueWidgetHarness(
        tester,
        testHarness: harness,
        cueUuid: cue.uuid,
      );

      cueHarness.addUnknownSlide('slide-unknown');
      await cueHarness.flushWrites();
      await tester.pumpAndSettle();

      expect(cueHarness.session.slideCount, 2);
      expect(
        find.byKey(cueHarnessJumpButtonKey('slide-unknown')),
        findsOneWidget,
      );
    });
  });
}
