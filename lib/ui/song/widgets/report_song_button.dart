import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/song/song.dart';
import '../../../services/bank/bank_of_song.dart';
import '../../../services/bank/report_song.dart';

class ReportSongButton extends ConsumerWidget {
  const ReportSongButton(this.song, {super.key});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (song.sourceBank == null) {
      return SizedBox.shrink();
    }

    final bank = ref.watch(bankOfSongProvider(song));

    return bank.when(
      data: (bank) {
        final contactEmail = bank?.contactEmail;
        if (contactEmail != null && contactEmail.isNotEmpty) {
          return TextButton.icon(
            onPressed: () => bank?.sendReportEmail(song),
            label: Text('Hibajelentés'),
            icon: Icon(Icons.textsms_outlined),
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
