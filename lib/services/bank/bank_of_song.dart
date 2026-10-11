import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/bank/bank.dart';
import '../../data/database.dart';
import '../../data/song/song.dart';

part 'bank_of_song.g.dart';

/// The bank a song belongs to, loaded from the database.
Future<Bank> loadBankOfSong(Song song) {
  if (song.sourceBank == null) {
    throw Exception("Can't get Bank object for song with no song bank set");
  }
  return (db.banks.select()..where((b) => b.uuid.equals(song.sourceBank!)))
      .getSingle();
}

@riverpod
Future<Bank> bankOfSong(Ref ref, Song song) => loadBankOfSong(song);
