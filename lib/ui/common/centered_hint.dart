import 'package:flutter/material.dart';

class CenteredHint extends StatelessWidget {
  const CenteredHint(this.title, {this.iconData, this.alignment, super.key});

  final String title;
  final IconData? iconData;
  final Alignment? alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment ?? Alignment.center,
      child: IntrinsicWidth(
        child: ListTile(leading: Icon(iconData), title: Text(title)),
      ),
    );
  }
}
