import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sofar/data/cue/cue.dart';
import 'package:sofar/data/cue/slide.dart';
import 'package:sofar/data/log/provider.dart';
import 'package:sofar/services/app_links/app_links.dart';
import 'package:sofar/services/app_version/check_new_version.dart';
import 'package:sofar/services/connectivity/provider.dart';
import 'package:sofar/ui/base/scaffold.dart';
import 'package:sofar/ui/cue/session/cue_session.dart';
import 'package:sofar/ui/cue/session/session_provider.dart';

class _FakeConnection extends Connection {
  @override
  ConnectionType build() => ConnectionType.unlimited;
}

class _FakeActiveCueSession extends ActiveCueSession {
  _FakeActiveCueSession(this.initialSession);

  final CueSession? initialSession;

  @override
  Future<CueSession?> build() async => initialSession;

  @override
  Future<void> unload() async {
    state = const AsyncValue.data(null);
  }
}

Future<CueSession> createCueSession() async {
  final cue = Cue(1, 'cue-1', 'Aktiv lista', 'Leiras', 1, []);
  cue.addSlide(
    UnknownTypeSlide(
      {'slideType': 'unknown', 'uuid': 'slide-1', 'comment': null},
      'slide-1',
      null,
    ),
  );
  await cue.getRevivedSlides();
  return CueSession(cue: cue, currentSlideUuid: 'slide-1');
}

Future<void> pumpShellScaffold(
  WidgetTester tester, {
  required Size size,
  required String initialLocation,
  CueSession? session,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => BaseScaffold(child: child),
        routes: [
          GoRoute(
            path: '/bank',
            builder: (context, state) =>
                const SizedBox.expand(child: Text('Bank page')),
          ),
          GoRoute(
            path: '/cues',
            builder: (context, state) =>
                const SizedBox.expand(child: Text('Cue page')),
          ),
          GoRoute(
            path: '/song/:uuid',
            builder: (context, state) => SizedBox.expand(
              child: Text('Song ${state.pathParameters['uuid']}'),
            ),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shouldNavigateProvider.overrideWith((ref) => const Stream.empty()),
        checkNewVersionProvider.overrideWith((ref) async => null),
        unreadLogCountProvider.overrideWith((ref) => 0),
        connectionProvider.overrideWith(_FakeConnection.new),
        activeCueSessionProvider.overrideWith(
          () => _FakeActiveCueSession(session),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the active cue overlay on mobile bank routes', (
    tester,
  ) async {
    await pumpShellScaffold(
      tester,
      size: const Size(600, 900),
      initialLocation: '/bank',
      session: await createCueSession(),
    );

    expect(find.text('Aktiv lista'), findsOneWidget);
    expect(find.byTooltip('Aktív lista bezárása'), findsOneWidget);
  });

  testWidgets('does not show the active cue overlay on desktop routes', (
    tester,
  ) async {
    await pumpShellScaffold(
      tester,
      size: const Size(1200, 900),
      initialLocation: '/bank',
      session: await createCueSession(),
    );

    expect(find.text('Aktiv lista'), findsNothing);
  });

  testWidgets('does not show the active cue overlay outside bank and song', (
    tester,
  ) async {
    await pumpShellScaffold(
      tester,
      size: const Size(600, 900),
      initialLocation: '/cues',
      session: await createCueSession(),
    );

    expect(find.text('Aktiv lista'), findsNothing);
  });

  testWidgets('closing the overlay clears the active cue session', (
    tester,
  ) async {
    await pumpShellScaffold(
      tester,
      size: const Size(600, 900),
      initialLocation: '/bank',
      session: await createCueSession(),
    );

    await tester.tap(find.byTooltip('Aktív lista bezárása'));
    await tester.pumpAndSettle();

    expect(find.text('Aktiv lista'), findsNothing);
  });
}
