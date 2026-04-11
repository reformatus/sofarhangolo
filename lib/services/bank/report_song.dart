import 'package:mailto/mailto.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/bank/bank.dart';
import '../../data/song/song.dart';

extension SongReport on Bank {
  Future<bool> sendReportEmail(Song song) async {
    if (contactEmail == null || contactEmail!.isEmpty) {
      throw Exception("Can't send feedback for Bank with no contact email!");
    }

    Mailto mail = Mailto(
      to: [contactEmail!],
      subject: 'Énekhiba - ${song.title}',
      body:
          """
Írd le, milyen hibát találtál:




---------------
Az alábbi adatokat ne töröld ki.
Utoljára frissítve: $lastUpdated
""",
    );

    return await launchUrl(Uri.parse(mail.toString()));
  }
}
