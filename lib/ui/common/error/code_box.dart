import 'package:flutter/material.dart';

/// Scrollable monospace box for technical text (error messages, stacks).
class ErrorCodeBox extends StatelessWidget {
  const ErrorCodeBox(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: 100),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Courier New',
            ), // todo is available on android?
          ),
        ),
      ),
    );
  }
}
