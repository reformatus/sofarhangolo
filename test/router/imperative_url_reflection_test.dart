import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  tearDown(() {
    GoRouter.optionURLReflectsImperativeAPIs = false;
  });

  testWidgets('imperative push updates the route information when enabled', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/song/:uuid', builder: (_, __) => const SizedBox()),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.toString(), '/');

    router.push('/song/song-123');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.toString(), '/');

    GoRouter.optionURLReflectsImperativeAPIs = true;

    final reflectingRouter = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(path: '/song/:uuid', builder: (_, __) => const SizedBox()),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: reflectingRouter));
    await tester.pumpAndSettle();

    reflectingRouter.push('/song/song-123');
    await tester.pumpAndSettle();

    expect(
      reflectingRouter.routeInformationProvider.value.uri.toString(),
      '/song/song-123',
    );
  });
}
