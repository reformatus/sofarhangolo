import 'package:drift/drift.dart';
import 'package:uuid/v4.dart';

import '../../data/bank/bank.dart';
import '../../data/database.dart';
import '../../data/log/logger.dart';
import '../../data/song/song.dart';
import '../../data/song/song_link.dart';
import '../assets/pick_asset.dart';
import '../assets/write_song_asset.dart';
import '../bank/banks.dart';
import 'delete_for_song.dart';

/// Fetches the bytes of an attachment field for [song] (e.g. by downloading it
/// from the song's bank). Returns null when the field has no attachment.
typedef AssetFetcher = Future<Uint8List?> Function(Song song, String fieldName);

/// Checks that [song] may live in the local bank and returns it with its
/// sourceBank assigned to the local bank when it had none.
Future<Song> _asLocalSong(Song song, String caller) async {
  final local = await localBank();

  if (song.sourceBank != null && song.sourceBank != local.uuid) {
    throw ArgumentError.value(
      song.sourceBank,
      'song.sourceBank',
      '$caller only accepts songs of the local bank',
    );
  }

  return song.sourceBank == null ? song.copyWith(sourceBank: local.uuid) : song;
}

/// Creates a new local song (insert only: throws if the uuid already exists).
///
/// Local songs live in the built-in local bank ([BankAccess.local]), so
/// they are never touched by bank updates and can be freely edited. Songs
/// coming from a regular bank must not be written this way.
Future<Song> createLocalSong(Song song) async {
  final owned = await _asLocalSong(song, 'createLocalSong');
  await db.into(db.songs).insert(owned);
  return owned;
}

/// Updates an existing local song by uuid (update only: never inserts).
///
/// Returns null, writing nothing, when the song no longer exists (e.g. it was
/// deleted while a save was in flight). Attachment references (the
/// [assetFieldExtensions] keys of the contentMap) are owned exclusively by
/// [writeLocalSongAsset]/[removeLocalSongAsset]: they are always preserved
/// from the stored row, whatever [song] holds for them. Returns the song as
/// stored.
Future<Song?> updateLocalSong(Song song) async {
  final owned = await _asLocalSong(song, 'updateLocalSong');

  return db.transaction(() async {
    final current =
        await (db.songs.select()..where((s) => s.uuid.equals(owned.uuid)))
            .getSingleOrNull();
    if (current == null) return null;

    final contentMap = Map<String, Object>.of(owned.contentMap);
    for (final key in assetFieldExtensions.keys) {
      contentMap.remove(key);
      final stored = current.contentMap[key];
      if (stored != null) contentMap[key] = stored;
    }
    final toStore = owned.copyWith(contentMap: contentMap);

    await (db.update(
      db.songs,
    )..where((s) => s.uuid.equals(toStore.uuid))).write(
      SongsCompanion(
        sourceBank: Value(toStore.sourceBank),
        contentMap: Value(toStore.contentMap),
        title: Value(toStore.title),
        lyrics: Value(toStore.lyrics),
        lyricsFormat: Value(toStore.lyricsFormat),
        variationOf: Value(toStore.variationOf),
        keyField: Value(toStore.keyField),
        ownership: Value(toStore.ownership),
      ),
    );
    return toStore;
  });
}

/// Copies [song] (typically a bank song) into a new editable local song.
///
/// The copy:
/// - gets a fresh uuid and lives in the local bank,
/// - carries its own copies of [song]'s `svg`/`pdf` attachments, fetched with
///   [fetchAsset] and stored as local assets, so the copy keeps its sheet
///   music/PDF independently of the bank. This is best-effort: a field that
///   fails to fetch is logged and skipped so the copy is still created. Pass
///   a null [fetchAsset] to skip attachments entirely,
/// - does not keep [Song.variationOf], so bank updates never treat it as a
///   variation of the original,
/// - is linked back to [song] with a [SongLinkType.localCopyOf] link that
///   also remembers the original's [Song.contentHash] at copy time, so the
///   UI can detect when the original changed since the copy was made.
Future<Song> copySongToLocal(Song song, {AssetFetcher? fetchAsset}) async {
  // Network happens before the transaction: it must not be held open.
  final fetched = <String, Uint8List>{};
  if (fetchAsset != null) {
    for (final field in assetFieldExtensions.keys) {
      if (song.contentString(field) == null) continue;

      try {
        final bytes = await fetchAsset(song, field);
        if (bytes != null) fetched[field] = bytes;
      } catch (error, stackTrace) {
        log.warning(
          'Nem sikerült átmásolni a(z) $field csatolmányt a másolatba.',
          error,
          stackTrace,
        );
      }
    }
  }

  final uuid = UuidV4().generate();
  final hashes = {
    for (final entry in fetched.entries) entry.key: localAssetHash(entry.value),
  };

  final local = await _asLocalSong(
    Song(
      uuid: uuid,
      title: song.title,
      lyrics: song.lyrics,
      lyricsFormat: song.lyricsFormat,
      keyField: song.keyField,
      contentMap: {
        ...Map.of(song.contentMap)
          ..remove('svg')
          ..remove('pdf'),
        ...hashes,
      },
    ),
    'copySongToLocal',
  );

  await db.transaction(() async {
    await db.into(db.songs).insert(local);
    await db.songLinks.insert().insert(
      SongLinksCompanion.insert(
        sourceUuid: local.uuid,
        type: SongLinkType.localCopyOf,
        targetUuid: song.uuid,
        targetContentHash: Value(song.contentHash),
      ),
    );
    for (final entry in fetched.entries) {
      await db.assets.insert().insert(
        AssetsCompanion.insert(
          songUuid: local.uuid,
          fieldName: entry.key,
          content: entry.value,
        ),
      );
    }
  });

  return local;
}

/// Deletes a local song together with its links and any cached assets, in
/// one transaction.
Future<void> deleteLocalSong(Song song) async {
  await db.transaction(() async {
    await db.songs.deleteWhere((s) => s.uuid.equals(song.uuid));
    await (db.songLinks.delete()..where((l) => l.sourceUuid.equals(song.uuid)))
        .go();
    await deleteAssetsForSong(song);
  });
}
