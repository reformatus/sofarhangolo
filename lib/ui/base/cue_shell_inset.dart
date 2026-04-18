import 'package:flutter/widgets.dart';

enum CueShellPresentation { inline, bottomOverlay }

class CueShellInset extends InheritedWidget {
  const CueShellInset({
    required this.bottomInset,
    this.presentation = CueShellPresentation.inline,
    required super.child,
    super.key,
  });

  final double bottomInset;
  final CueShellPresentation presentation;

  static double bottomInsetOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<CueShellInset>()
            ?.bottomInset ??
        0;
  }

  static CueShellPresentation presentationOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<CueShellInset>()
            ?.presentation ??
        CueShellPresentation.inline;
  }

  static bool showsBottomOverlayOf(BuildContext context) {
    return presentationOf(context) == CueShellPresentation.bottomOverlay;
  }

  @override
  bool updateShouldNotify(CueShellInset oldWidget) {
    return oldWidget.bottomInset != bottomInset ||
        oldWidget.presentation != presentation;
  }
}
