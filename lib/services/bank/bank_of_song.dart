import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/bank/bank.dart';
import '../../data/database.dart';
import '../../data/song/song.dart';

part 'bank_of_song.g.dart';

@riverpod
Future<Bank?> bankOfSong(Ref ref, Song song) {
  final bankUuid = song.sourceBank;
  if (bankUuid == null) {
    return Future.value(null);
  }
  return (db.banks.select()..where((b) => b.uuid.equals(bankUuid)))
      .getSingleOrNull();
}
