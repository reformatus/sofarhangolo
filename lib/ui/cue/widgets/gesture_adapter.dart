import 'package:flutter/material.dart';

class CueSlideGestureAdapter extends StatefulWidget {
  const CueSlideGestureAdapter({
    required this.child,
    required this.onHorizontalDragStart,
    required this.onHorizontalDragUpdate,
    required this.onHorizontalDragEnd,
    required this.onHorizontalDragCancel,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final VoidCallback onHorizontalDragStart;
  final ValueChanged<double> onHorizontalDragUpdate;
  final ValueChanged<double> onHorizontalDragEnd;
  final VoidCallback onHorizontalDragCancel;

  @override
  State<CueSlideGestureAdapter> createState() => _CueSlideGestureAdapterState();
}

class _CueSlideGestureAdapterState extends State<CueSlideGestureAdapter> {
  final Set<int> _activePointers = <int>{};
  bool _horizontalDragActive = false;
  bool _cancelledByMultitouch = false;

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);

    if (_activePointers.length > 1 && _horizontalDragActive) {
      _cancelledByMultitouch = true;
      _horizontalDragActive = false;
      widget.onHorizontalDragCancel();
    }
  }

  void _handlePointerFinished(PointerEvent event) {
    _activePointers.remove(event.pointer);
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (!widget.enabled || _activePointers.length != 1) return;

    _cancelledByMultitouch = false;
    _horizontalDragActive = true;
    widget.onHorizontalDragStart();
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_horizontalDragActive || _cancelledByMultitouch) return;
    if (_activePointers.length != 1) return;

    final deltaDx = details.primaryDelta;
    if (deltaDx == null || deltaDx == 0) return;

    widget.onHorizontalDragUpdate(deltaDx);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_horizontalDragActive) return;

    final cancelledByMultitouch = _cancelledByMultitouch;
    _horizontalDragActive = false;
    _cancelledByMultitouch = false;

    if (cancelledByMultitouch) {
      widget.onHorizontalDragCancel();
      return;
    }

    widget.onHorizontalDragEnd(details.primaryVelocity ?? 0);
  }

  void _handleHorizontalDragCancel() {
    if (!_horizontalDragActive) return;

    _horizontalDragActive = false;
    _cancelledByMultitouch = false;
    widget.onHorizontalDragCancel();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerFinished,
      onPointerCancel: _handlePointerFinished,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _handleHorizontalDragStart,
        onHorizontalDragUpdate: _handleHorizontalDragUpdate,
        onHorizontalDragEnd: _handleHorizontalDragEnd,
        onHorizontalDragCancel: _handleHorizontalDragCancel,
        child: widget.child,
      ),
    );
  }
}
