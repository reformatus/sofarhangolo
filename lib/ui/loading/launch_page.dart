import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../services/app_links/launch_resolution.dart';
import '../../services/app_links/web_initial_app_uri.dart';
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
    syncWebBrowserUrlToAppRoute(widget.launchUri.toString(), config: appConfig);
    _handleLaunch();
  }

  Future<void> _handleLaunch() async {
    if (_handled) return;
    _handled = true;

    try {
      final destination = await resolveLaunchRoute(widget.launchUri);
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
