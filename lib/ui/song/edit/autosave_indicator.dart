import 'package:flutter/material.dart';

/// State of the editor's (mock) autosave.
enum AutosaveStatus {
  /// Nothing to show; the indicator collapses away.
  idle,

  /// A save is in flight: spinner + label.
  saving,

  /// Just saved: check + label, shown briefly.
  saved,

  /// Saved and settled: the label is hidden and only the check remains.
  upToDate,

  /// The last save attempt failed; the indicator stays visible and is
  /// tappable to retry.
  error,
}

/// Subtle autosave status for the editor app bar.
///
/// The text and the icon/loading are handled independently: the label fades
/// on its own, while the icon lives in a fixed-size slot, so switching
/// between the spinner, the check and the error icon never resizes or moves
/// it. There is no background pill. The [AutosaveStatus.error] state is
/// tappable to retry ([onRetry]).
class AutosaveIndicator extends StatelessWidget {
  const AutosaveIndicator({super.key, required this.status, this.onRetry});

  final AutosaveStatus status;
  final VoidCallback? onRetry;

  static const _fade = Duration(milliseconds: 180);

  /// Fixed size of the icon/loading slot.
  static const double _iconSlot = 20;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: _fade,
      child: status == AutosaveStatus.idle
          ? const SizedBox.shrink(key: ValueKey('idle'))
          : Row(
              // Stable key: the icon/text swap in place instead of the whole
              // row cross-fading (which would move the icon).
              key: const ValueKey('indicator'),
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: _fade,
                  child: _label(context, colors),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  key: const ValueKey('icon-slot'),
                  dimension: _iconSlot,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: _fade,
                      child: _icon(context, colors),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _label(BuildContext context, ColorScheme colors) {
    final text = switch (status) {
      AutosaveStatus.saving => 'Mentés',
      AutosaveStatus.saved => 'Mentve',
      AutosaveStatus.error => 'Mentés sikertelen',
      AutosaveStatus.idle || AutosaveStatus.upToDate => null,
    };
    if (text == null) {
      return const SizedBox.shrink(key: ValueKey('no-label'));
    }
    final foreground = status == AutosaveStatus.error
        ? colors.error
        : colors.onSurfaceVariant;
    return Text(
      text,
      key: ValueKey('label-$status'),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: foreground),
    );
  }

  Widget _icon(BuildContext context, ColorScheme colors) {
    return switch (status) {
      AutosaveStatus.saving => SizedBox.square(
        key: const ValueKey('icon-saving'),
        dimension: _iconSlot,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
      ),
      AutosaveStatus.saved || AutosaveStatus.upToDate => Icon(
        Icons.check,
        key: const ValueKey('icon-check'),
        size: _iconSlot,
        color: colors.primary,
      ),
      AutosaveStatus.error => Tooltip(
        message: 'Újrapróbálás',
        child: InkWell(
          onTap: onRetry,
          customBorder: const CircleBorder(),
          child: Icon(
            Icons.error_outline,
            key: const ValueKey('icon-error'),
            size: _iconSlot,
            color: colors.error,
          ),
        ),
      ),
      AutosaveStatus.idle => const SizedBox.shrink(key: ValueKey('icon-none')),
    };
  }
}
