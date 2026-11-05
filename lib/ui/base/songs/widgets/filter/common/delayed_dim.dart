import 'dart:async';

import 'package:flutter/material.dart';

/// Dims [child] while [loading], but only once that has lasted longer than
/// [threshold]; a load that finishes sooner never dims.
class DelayedDim extends StatefulWidget {
  const DelayedDim({
    required this.loading,
    required this.child,
    this.threshold = const Duration(milliseconds: 200),
    this.dimOpacity = 0.45,
    super.key,
  });

  final bool loading;
  final Widget child;

  /// How long [loading] may last before the dim starts.
  final Duration threshold;

  final double dimOpacity;

  @override
  State<DelayedDim> createState() => _DelayedDimState();
}

class _DelayedDimState extends State<DelayedDim> {
  Timer? _timer;
  bool _dim = false;

  @override
  void initState() {
    super.initState();
    if (widget.loading) _startTimer();
  }

  @override
  void didUpdateWidget(DelayedDim oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading == oldWidget.loading) return;
    if (widget.loading) {
      _startTimer();
    } else {
      _timer?.cancel();
      _timer = null;
      _dim = false;
    }
  }

  void _startTimer() {
    _timer = Timer(widget.threshold, () {
      if (mounted) setState(() => _dim = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: Durations.short4,
      opacity: _dim ? widget.dimOpacity : 1,
      child: widget.child,
    );
  }
}
