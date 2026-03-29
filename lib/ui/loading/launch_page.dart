import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/app_links/navigation.dart';
import '../../services/cue/import_from_link.dart';
import '../common/error/card.dart';

class LaunchPage extends StatefulWidget {
  const LaunchPage({required this.launchUri, super.key});

  final Uri launchUri;

  @override
  State<LaunchPage> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage> {
  Object? _error;
  StackTrace? _stackTrace;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _handleLaunch();
  }

  Future<void> _handleLaunch() async {
    if (_handled) return;
    _handled = true;

    try {
      final destination = await _resolveLaunchDestination(widget.launchUri);
      if (!mounted) return;
      context.go(destination);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _stackTrace = stackTrace;
      });
    }
  }

  Future<String> _resolveLaunchDestination(Uri launchUri) async {
    switch (launchUri.path) {
      case '/launch/cueData':
        final encodedData = launchUri.queryParameters['data'];
        if (encodedData == null) {
          throw Exception('Hiányzik a lista adata a linkből.');
        }
        final result = await importCueFromCompressedData(
          encodedData,
          launchUri.queryParameters,
        );
        return result.getNavigationPath();
      case '/launch/cueJson':
        final jsonString = launchUri.queryParameters['data'];
        if (jsonString == null) {
          throw Exception('Hiányzik a lista adata a linkből.');
        }
        final result = await importCueFromJson(
          jsonString,
          launchUri.queryParameters,
        );
        return result.getNavigationPath();
      default:
        return initialRouteFromAppUri(launchUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hiba')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LErrorCard.fromError(
                error: _error!,
                stackTrace: _stackTrace,
                title: 'Nem sikerült megnyitni a linket',
                icon: Icons.link_off,
              ),
            ),
          ),
        ),
      );
    }

    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
