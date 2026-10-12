import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/bank/bank.dart';
import '../../../data/song/song.dart';
import '../../../services/bank/bank_of_song.dart';
import '../../../services/bank/report_song.dart';

class ReportSongButton extends ConsumerWidget {
  const ReportSongButton(this.song, {this.filled = false, super.key});

  final Song song;

  /// Filled (primary) instead of outlined. Notice cards use the filled form
  /// when the report is the card's main action; sidebars keep the outlined one
  /// so the sidebar's buttons stay quiet.
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (song.sourceBank == null) {
      return SizedBox.shrink();
    }

    final bank = ref.watch(bankOfSongProvider(song));

    return bank.when(
      data: (bank) {
        // Local songs are never reported back to a remote bank.
        if (bank.access == BankAccess.local) {
          return SizedBox.shrink();
        }
        if (bank.contactEmail != null && bank.contactEmail!.isNotEmpty) {
          final icon = Icon(Icons.textsms_outlined);
          final label = Text('Hibajelentés');
          void onPressed() => bank.sendReportEmail(song);
          return filled
              ? FilledButton.icon(
                  onPressed: onPressed,
                  label: label,
                  icon: icon,
                )
              : OutlinedButton.icon(
                  onPressed: onPressed,
                  label: label,
                  icon: icon,
                );
        } else {
          return SizedBox.shrink();
        }
      },
      error: (error, stack) => SizedBox.shrink(),
      loading: () => SizedBox.shrink(),
    );
  }
}
