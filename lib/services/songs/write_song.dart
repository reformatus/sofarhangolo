import 'package:drift/drift.dart';
import 'package:uuid/v4.dart';

import '../../data/bank/bank.dart';
import '../../data/database.dart';
import '../../data/song/song.dart';
import '../../data/song/song_link.dart';
import '../bank/banks.dart';
import 'delete_for_song.dart';

/// Creates a new local song, or updates an existing one by uuid.
///
/// Local songs live in the built-in local bank ([BankAccess.local]), so
/// they are never touched by bank updates and can be freely edited. Songs
/// coming from a regular bank must not be written this way.
Future<Song> writeLocalSong(Song song) async {
  final local = await localBank();

  if (song.sourceBank != null && song.sourceBank != local.uuid) {
    throw ArgumentError.value(
      song.sourceBank,
      'song.sourceBank',
      'writeLocalSong only accepts songs of the local bank',
    );
  }

  final owned = song.sourceBank == null
      ? song.copyWith(sourceBank: local.uuid)
      : song;

  final updatedRows = await (db.update(
    db.songs,
  )..where((s) => s.uuid.equals(owned.uuid))).writeReturning(
    SongsCompanion(
      sourceBank: Value(owned.sourceBank),
      contentMap: Value(owned.contentMap),
      title: Value(owned.title),
      lyrics: Value(owned.lyrics),
      lyricsFormat: Value(owned.lyricsFormat),
      variationOf: Value(owned.variationOf),
      keyField: Value(owned.keyField),
      ownership: Value(owned.ownership),
    ),
  );

  if (updatedRows.isEmpty) {
    await db.into(db.songs).insert(owned);
  }
  return owned;
}

/// Copies [song] (typically a bank song) into a new editable local song.
///
/// The copy:
/// - gets a fresh uuid and lives in the local bank,
/// - loses asset references (`svg`/`pdf`) from its content, so asset views
///   never try to fetch the original's bank assets for it,
/// - does not keep [Song.variationOf], so bank updates never treat it as a
///   variation of the original,
/// - is linked back to [song] with a [SongLinkType.localCopyOf] link that
///   also remembers the original's [Song.contentHash] at copy time, so the
///   UI can detect when the original changed since the copy was made.
Future<Song> copySongToLocal(Song song) async {
  final local = await writeLocalSong(
    Song(
      uuid: UuidV4().generate(),
      title: song.title,
      lyrics: song.lyrics,
      lyricsFormat: song.lyricsFormat,
      keyField: song.keyField,
      contentMap:
          Map.of(song.contentMap)
            ..remove('svg')
            ..remove('pdf'),
    ),
  );

  await db.songLinks.insert().insert(
    SongLinksCompanion.insert(
      sourceUuid: local.uuid,
      type: SongLinkType.localCopyOf,
      targetUuid: song.uuid,
      targetContentHash: Value(song.contentHash),
    ),
  );

  return local;
}

/// Deletes a local song together with its links and any cached assets.
Future<void> deleteLocalSong(Song song) async {
  await db.songs.deleteWhere((s) => s.uuid.equals(song.uuid));
  await (db.songLinks.delete()
        ..where((l) => l.sourceUuid.equals(song.uuid)))
      .go();
  await deleteAssetsForSong(song);
}
