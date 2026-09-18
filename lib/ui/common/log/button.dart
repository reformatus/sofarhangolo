import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/log/provider.dart';
import 'dialog.dart';

class LogButton extends ConsumerWidget {
  const LogButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadLogCount = ref.watch(unreadLogCountProvider);

    onPressed() =>
        showDialog(context: context, builder: (context) => LogViewDialog());

    return Badge(
      label: Text(unreadLogCount.toString()),
      isLabelVisible: unreadLogCount > 0,
      child: unreadLogCount > 0
          ? IconButton.outlined(
              onPressed: onPressed,
              tooltip: "Napló",
              icon: Icon(Icons.monitor_heart),
            )
          : IconButton(
              onPressed: onPressed,
              tooltip: "Napló",
              icon: Icon(Icons.monitor_heart_outlined),
            ),
    );
  }
}
