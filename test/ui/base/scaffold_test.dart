import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/data/log/provider.dart';
import 'package:sofarhangolo/services/app_links/app_links.dart';
import 'package:sofarhangolo/services/app_version/check_new_version.dart';
import 'package:sofarhangolo/services/connectivity/provider.dart';
import 'package:sofarhangolo/ui/base/scaffold.dart';
import 'package:sofarhangolo/ui/base/widgets/active_cue_shell_card.dart';
import 'package:sofarhangolo/ui/cue/session/cue_session.dart';
import 'package:sofarhangolo/ui/cue/session/session_provider.dart';

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
          GoRoute(
            path: '/cue/:uuid/edit',
            builder: (context, state) => SizedBox.expand(
              child: Text(
                'Cue edit ${state.pathParameters['uuid']} ${state.uri.queryParameters['slide']}',
              ),
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
    expect(find.byTooltip('Lista megnyitása'), findsOneWidget);
  });

  testWidgets('shows desktop cue shell controls on desktop routes', (
    tester,
  ) async {
    await pumpShellScaffold(
      tester,
      size: const Size(1200, 900),
      initialLocation: '/bank',
      session: await createCueSession(),
    );

    expect(find.text('Aktiv lista'), findsWidgets);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
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

  testWidgets('overlay opens cue sheet on mobile bank routes', (tester) async {
    await pumpShellScaffold(
      tester,
      size: const Size(600, 900),
      initialLocation: '/bank',
      session: await createCueSession(),
    );

    await tester.tap(find.byTooltip('Lista megnyitása'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Bezárás'), findsOneWidget);
  });

  testWidgets('desktop indicator tap opens cue editor page', (tester) async {
    await pumpShellScaffold(
      tester,
      size: const Size(1200, 900),
      initialLocation: '/bank',
      session: await createCueSession(),
    );

    await tester.tap(find.byType(ActiveCueSidebarIndicator));
    await tester.pumpAndSettle();

    expect(find.text('Cue edit cue-1 slide-1'), findsOneWidget);
  });

  testWidgets('tablet chevron opens cue drawer', (tester) async {
    await pumpShellScaffold(
      tester,
      size: const Size(900, 700),
      initialLocation: '/bank',
      session: await createCueSession(),
    );

    expect(find.byTooltip('Lista bezárása'), findsNothing);

    await tester.tap(find.byTooltip('Lista megnyitása').first);
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);
  });

  testWidgets('narrow landscape rail layout still opens cue drawer', (
    tester,
  ) async {
    await pumpShellScaffold(
      tester,
      size: const Size(680, 400),
      initialLocation: '/bank',
      session: await createCueSession(),
    );

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);

    await tester.tap(find.byTooltip('Lista megnyitása').first);
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);
  });
}
