import 'package:flutter/widgets.dart';

class CueShellInset extends InheritedWidget {
  const CueShellInset({
    required this.bottomInset,
    required super.child,
    super.key,
  });

  final double bottomInset;

  static double bottomInsetOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<CueShellInset>()
            ?.bottomInset ??
        0;
  }

  @override
  bool updateShouldNotify(CueShellInset oldWidget) {
    return oldWidget.bottomInset != bottomInset;
  }
}
