import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/services/ui/presentation_fullscreen_shared.dart';
import 'package:sofarhangolo/ui/cue/present/musician/page.dart';
import 'package:sofarhangolo/ui/cue/session/session_provider.dart';

import '../../harness/test_harness.dart';

class _FakePresentationFullscreenController
    implements PresentationFullscreenController {
  _FakePresentationFullscreenController({required bool isFullscreen})
    : _isFullscreen = isFullscreen;

  final _changes = StreamController<bool>.broadcast();
  bool _isFullscreen;

  @override
  bool get isFullscreen => _isFullscreen;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<void> prepareForNavigation() async {}

  @override
  Future<void> enter() async {}

  @override
  Future<void> exit() async {
    _isFullscreen = false;
  }

  void emit(bool isFullscreen) {
    _isFullscreen = isFullscreen;
    _changes.add(isFullscreen);
  }

  Future<void> dispose() => _changes.close();
}

void main() {
  group('CuePresentMusicianPage', () {
    late LyricDatabase testDb;
    late TestHarness harness;

    setUp(() async {
      testDb = createTestDatabase();
      db = testDb;
      harness = TestHarness();

      await db
          .into(db.cues)
          .insertReturning(
            CuesCompanion(
              id: const Value.absent(),
              uuid: const Value('cue-1'),
              title: const Value('Cue title'),
              description: const Value('Cue description'),
              cueVersion: Value(currentCueVersion),
              content: const Value([
                {'slideType': 'unknown', 'uuid': 'slide-1', 'comment': null},
              ]),
            ),
          );

      await harness.container
          .read(activeCueSessionProvider.notifier)
          .load('cue-1');
    });

    tearDown(() async {
      harness.dispose();
      await testDb.close();
    });

    testWidgets(
      'leaves the presentation route when fullscreen exits externally',
      (tester) async {
        final session = harness.container.read(activeCueSessionProvider).value!;
        final fullscreenController = _FakePresentationFullscreenController(
          isFullscreen: true,
        );

        final router = GoRouter(
          initialLocation: '/cue/cue-1/present/musician',
          routes: [
            GoRoute(
              path: '/cue/:uuid/edit',
              builder: (context, state) =>
                  Text('edit:${state.uri.queryParameters['slide']}'),
            ),
            GoRoute(
              path: '/cue/:uuid/present/musician',
              builder: (context, state) => CuePresentMusicianPage(
                session,
                fullscreenController: fullscreenController,
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: harness.container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        fullscreenController.emit(false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));

        expect(router.state.uri.path, '/cue/cue-1/edit');
        expect(router.state.uri.queryParameters['slide'], 'slide-1');
        expect(find.byType(CuePresentMusicianPage), findsNothing);

        await fullscreenController.dispose();
      },
    );
  });
}
