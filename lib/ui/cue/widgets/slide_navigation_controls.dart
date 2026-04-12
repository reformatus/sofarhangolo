import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_provider.dart';

class CueSlideNavigationControls extends ConsumerWidget {
  const CueSlideNavigationControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slideIndex = ref.watch(slideIndexProvider);
    final canNavigatePrevious = ref.watch(canNavigatePreviousProvider);
    final canNavigateNext = ref.watch(canNavigateNextProvider);
    final label = slideIndex == null
        ? '0. / 0 dia'
        : '${slideIndex.index + 1}. / ${slideIndex.total} dia';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: canNavigatePrevious
              ? () => ref.read(activeCueSessionProvider.notifier).navigate(-1)
              : null,
          icon: const Icon(Icons.navigate_before),
          tooltip: 'Előző dia',
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: canNavigateNext
              ? () => ref.read(activeCueSessionProvider.notifier).navigate(1)
              : null,
          icon: const Icon(Icons.navigate_next),
          tooltip: 'Következő dia',
        ),
        const SizedBox(width: 16),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
