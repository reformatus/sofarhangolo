import 'package:drift/drift.dart';
import 'package:uuid/v4.dart';

import '../../../data/cue/cue.dart';
import '../../../data/database.dart';
import '../../../data/song/song.dart';
import '../../../data/song/song_link.dart';
import '../../assets/pick_asset.dart';
import '../../assets/write_song_asset.dart';
import '../../bank/banks.dart';
import '../../cue/write_cue.dart';
import '../write_song.dart';
import 'song_bundle.dart';

/// What importing one incoming song would do (see DECISIONS.md, "Receive
/// rules"). Decided by [planSongBundleImport], re-decided inside the apply
/// transaction in case the database changed in between.
enum ImportOutcome {
  /// Unknown uuid, no matching local copy: becomes a new local song.
  newSong,

  /// Same uuid, same content: only checkpoints are merged.
  identical,

  /// Same uuid; the incoming song was built on my current version
  /// (my hash is in its checkpoints): replaced silently.
  fastForward,

  /// Same uuid; the incoming song is a version I already had (its hash is in
  /// my checkpoints): ignored.
  stale,

  /// Same uuid, diverged. Needs a choice: [ImportChoice.overwrite] or
  /// [ImportChoice.keepBoth].
  conflict,

  /// Unknown uuid, but I have an independent copy of the same bank song, with
  /// the same content: ignored (cue slides are pointed at my copy).
  identicalSibling,

  /// Unknown uuid, I have an independent copy of the same bank song with
  /// different content. Needs a choice: [ImportChoice.replace] or
  /// [ImportChoice.keepBoth].
  sibling,

  /// Cannot be imported (see [PlannedSong.error]); nothing is written.
  error,
}

/// The user's decision for a [ImportOutcome.conflict] or
/// [ImportOutcome.sibling] song.
enum ImportChoice {
  /// Conflict: my song's content becomes the incoming one (uuid kept).
  overwrite,

  /// Sibling: my copy's content becomes the incoming one (my uuid kept, so
  /// my cues stay valid; incoming cue slides are pointed at it).
  replace,

  /// Create the incoming song as an additional song under a fresh uuid
  /// (title unchanged), linked with [SongLinkType.importedCopyOf].
  keepBoth,
}

/// What to do when the bundle's cue has the same uuid as an existing cue.
enum CueImportChoice { overwrite, keepBoth, skip }

class PlannedSong {
  final BundledSong incoming;
  final ImportOutcome outcome;

  /// My song it was matched with: the same-uuid song (conflict, stale, ...)
  /// or the sibling copy. Null for [ImportOutcome.newSong]/[error].
  final Song? existing;

  /// Only for [ImportOutcome.conflict] on a song copied from a bank song:
  /// the incoming checkpoints contain my oldest checkpoint (the bank original
  /// at copy time) but none of my later ones, i.e. it descends from the
  /// original rather than my edits. A heuristic for wording the dialog.
  final bool descendsFromOriginal;

  final String? error;

  const PlannedSong(
    this.incoming,
    this.outcome, {
    this.existing,
    this.descendsFromOriginal = false,
    this.error,
  });

  String get uuid => incoming.uuid;
  String get title => incoming.song.title;

  bool get needsChoice =>
      outcome == ImportOutcome.conflict || outcome == ImportOutcome.sibling;

  /// The choices that make sense for this song (empty when none is needed).
  List<ImportChoice> get choices => switch (outcome) {
    ImportOutcome.conflict => const [
      ImportChoice.overwrite,
      ImportChoice.keepBoth,
    ],
    ImportOutcome.sibling => const [
      ImportChoice.replace,
      ImportChoice.keepBoth,
    ],
    _ => const [],
  };
}

class ImportPlan {
  final List<PlannedSong> songs;

  /// The bundle's cue (`Cue.toJson()` shape), or null.
  final Map<String, dynamic>? cue;

  /// A stored cue with the same uuid; when set the UI should ask for a
  /// [CueImportChoice].
  final Cue? existingCue;

  /// Attachments that failed verification and were left out.
  final List<DroppedAttachment> droppedAttachments;

  const ImportPlan(
    this.songs,
    this.cue,
    this.existingCue,
    this.droppedAttachments,
  );

  List<PlannedSong> get needingChoice =>
      songs.where((s) => s.needsChoice).toList();
}

enum ImportAction {
  /// A new local song was created under the incoming uuid.
  created,

  /// An existing song's content was replaced.
  updated,

  /// Nothing about the song changed (checkpoints may have been merged).
  unchanged,

  /// Created under a fresh uuid next to the existing one.
  createdCopy,

  /// Not imported ([ImportOutcome.error]).
  skipped,
}

class SongImportResult {
  final String incomingUuid;
  final String title;
  final ImportOutcome outcome;
  final ImportAction action;

  /// The local song that now represents the incoming one (null if skipped).
  final String? resultingUuid;
  final String? error;

  const SongImportResult({
    required this.incomingUuid,
    required this.title,
    required this.outcome,
    required this.action,
    this.resultingUuid,
    this.error,
  });
}

enum CueImportAction { created, overwritten, createdCopy, skipped }

class BundleCueResult {
  /// The stored cue (the existing one when skipped).
  final Cue? cue;
  final CueImportAction action;
  const BundleCueResult(this.cue, this.action);
}

class ImportResult {
  final List<SongImportResult> songs;

  /// Incoming uuid -> local uuid, for every song whose local uuid differs
  /// (keep-both copies, replaced/identical siblings). Already applied to the
  /// cue's song slides.
  final Map<String, String> uuidRemap;
  final BundleCueResult? cue;
  final List<DroppedAttachment> droppedAttachments;

  const ImportResult(
    this.songs,
    this.uuidRemap,
    this.cue,
    this.droppedAttachments,
  );
}

class _Classified {
  final ImportOutcome outcome;
  final Song? existing;
  final bool descendsFromOriginal;
  final String? error;
  const _Classified(
    this.outcome, {
    this.existing,
    this.descendsFromOriginal = false,
    this.error,
  });
}

/// Reads and verifies [bytes] (throws a [SongBundleException]) and decides
/// the outcome for each song. Writes nothing.
Future<ImportPlan> planSongBundleImport(Uint8List bytes) async {
  final bundle = readSongBundle(bytes);
  final localUuid = (await localBank()).uuid;

  final planned = <PlannedSong>[];
  for (final incoming in bundle.songs) {
    final c = await _classify(incoming, localUuid);
    planned.add(
      PlannedSong(
        incoming,
        c.outcome,
        existing: c.existing,
        descendsFromOriginal: c.descendsFromOriginal,
        error: c.error,
      ),
    );
  }

  Cue? existingCue;
  final cueUuid = bundle.cue?['uuid'] as String?;
  if (cueUuid != null) {
    existingCue = await (db.cues.select()..where((c) => c.uuid.equals(cueUuid)))
        .getSingleOrNull();
  }

  return ImportPlan(
    planned,
    bundle.cue,
    existingCue,
    bundle.droppedAttachments,
  );
}

Future<_Classified> _classify(BundledSong incoming, String localUuid) async {
  final existing =
      await (db.songs.select()..where((s) => s.uuid.equals(incoming.uuid)))
          .getSingleOrNull();

  if (existing != null) {
    if (existing.sourceBank != localUuid) {
      return const _Classified(
        ImportOutcome.error,
        error: 'A dal uuid-ja egy banki dalhoz tartozik.',
      );
    }
    final mine = existing.contentHash;
    final theirs = incoming.contentHash;
    if (theirs == mine) {
      return _Classified(ImportOutcome.identical, existing: existing);
    }
    if (incoming.song.checkpoints.contains(mine)) {
      return _Classified(ImportOutcome.fastForward, existing: existing);
    }
    if (existing.checkpoints.contains(theirs)) {
      return _Classified(ImportOutcome.stale, existing: existing);
    }
    final first = existing.checkpoints.firstOrNull;
    final hasOriginal =
        await (db.songLinks.select()..where(
              (l) =>
                  l.sourceUuid.equals(existing.uuid) &
                  l.type.equals(SongLinkType.localCopyOf.index),
            ))
            .getSingleOrNull() !=
        null;
    final descends =
        hasOriginal &&
        first != null &&
        incoming.song.checkpoints.contains(first) &&
        !existing.checkpoints.skip(1).any(incoming.song.checkpoints.contains);
    return _Classified(
      ImportOutcome.conflict,
      existing: existing,
      descendsFromOriginal: descends,
    );
  }

  final origin = incoming.origin;
  if (origin != null) {
    // My local copies of the same bank song, oldest copy first. One with the
    // same content wins; otherwise the oldest is offered for replacing.
    final links =
        await (db.songLinks.select()
              ..where(
                (l) =>
                    l.targetUuid.equals(origin.bankSongUuid) &
                    l.type.equals(SongLinkType.localCopyOf.index),
              )
              ..orderBy([(l) => OrderingTerm.asc(l.id)]))
            .get();
    final siblings = <Song>[];
    for (final link in links) {
      final song =
          await (db.songs.select()
                ..where((s) => s.uuid.equals(link.sourceUuid)))
              .getSingleOrNull();
      if (song != null && song.sourceBank == localUuid) siblings.add(song);
    }
    if (siblings.isNotEmpty) {
      for (final s in siblings) {
        if (s.contentHash == incoming.contentHash) {
          return _Classified(ImportOutcome.identicalSibling, existing: s);
        }
      }
      return _Classified(ImportOutcome.sibling, existing: siblings.first);
    }
  }

  return const _Classified(ImportOutcome.newSong);
}

List<String> _capped(List<String> list) => list.length > maxSongCheckpoints
    ? list.sublist(list.length - maxSongCheckpoints)
    : list;

/// [mine] followed by the entries of [incoming] it lacks; then [hash] is
/// appended unless it already is the last entry.
List<String> _mergeCheckpoints(
  List<String> mine,
  List<String> incoming, [
  String? hash,
]) {
  final list = [...mine, ...incoming.where((c) => !mine.contains(c))];
  if (hash != null && (list.isEmpty || list.last != hash)) list.add(hash);
  return _capped(list);
}

/// Applies [plan] in one transaction (nothing is written if anything fails).
///
/// [choices] maps an incoming song uuid to the user's decision for songs that
/// need one; a missing or non-applicable entry means the non-destructive
/// [ImportChoice.keepBoth] for them. The outcome of every song is decided
/// again inside the transaction, so a database that changed since planning is
/// handled correctly. The bundle's cue, if any, gets its song slides remapped
/// to the local uuids and is written according to [cueChoice] when a cue with
/// its uuid exists already.
Future<ImportResult> applySongBundleImport(
  ImportPlan plan,
  Map<String, ImportChoice> choices, {
  CueImportChoice cueChoice = CueImportChoice.keepBoth,
}) async {
  final localUuid = (await localBank()).uuid;

  return db.transaction(() async {
    final results = <SongImportResult>[];
    final remap = <String, String>{};

    for (final planned in plan.songs) {
      final incoming = planned.incoming;
      final c = await _classify(incoming, localUuid);
      final song = incoming.song;

      SongImportResult result(ImportAction action, String? uuid) =>
          SongImportResult(
            incomingUuid: incoming.uuid,
            title: song.title,
            outcome: c.outcome,
            action: action,
            resultingUuid: uuid,
            error: c.error,
          );

      switch (c.outcome) {
        case ImportOutcome.error:
          results.add(result(ImportAction.skipped, null));

        case ImportOutcome.newSong:
          await _insertSong(incoming, incoming.uuid, localUuid);
          results.add(result(ImportAction.created, incoming.uuid));

        case ImportOutcome.identical:
        case ImportOutcome.stale:
        case ImportOutcome.identicalSibling:
          final mine = c.existing!;
          await _writeCheckpoints(
            mine.uuid,
            _mergeCheckpoints(mine.checkpoints, song.checkpoints),
          );
          if (mine.uuid != incoming.uuid) remap[incoming.uuid] = mine.uuid;
          results.add(result(ImportAction.unchanged, mine.uuid));

        case ImportOutcome.fastForward:
          await _replaceContent(c.existing!, incoming);
          results.add(result(ImportAction.updated, incoming.uuid));

        case ImportOutcome.conflict:
        case ImportOutcome.sibling:
          final mine = c.existing!;
          final choice = choices[incoming.uuid];
          final replace =
              choice == ImportChoice.overwrite ||
              choice == ImportChoice.replace;
          if (replace) {
            await _replaceContent(mine, incoming);
            if (mine.uuid != incoming.uuid) remap[incoming.uuid] = mine.uuid;
            results.add(result(ImportAction.updated, mine.uuid));
          } else {
            final fresh = UuidV4().generate();
            await _insertSong(incoming, fresh, localUuid);
            await db.songLinks.insert().insert(
              SongLinksCompanion.insert(
                sourceUuid: fresh,
                type: SongLinkType.importedCopyOf,
                targetUuid: incoming.uuid,
                targetContentHash: Value(incoming.contentHash),
              ),
            );
            remap[incoming.uuid] = fresh;
            results.add(result(ImportAction.createdCopy, fresh));
          }
      }
    }

    final cueResult = plan.cue == null
        ? null
        : await _applyCue(plan.cue!, remap, cueChoice);

    return ImportResult(results, remap, cueResult, plan.droppedAttachments);
  });
}

Future<void> _insertSong(
  BundledSong incoming,
  String uuid,
  String localUuid,
) async {
  final hash = incoming.contentHash;
  final checkpoints = _mergeCheckpoints(
    const [],
    incoming.song.checkpoints,
    hash,
  );
  await db
      .into(db.songs)
      .insert(
        incoming.song.copyWith(
          uuid: uuid,
          sourceBank: localUuid,
          checkpoints: checkpoints,
        ),
      );
  for (final entry in incoming.assets.entries) {
    await putLocalAssetRow(uuid, entry.key, entry.value);
  }
  final origin = incoming.origin;
  if (origin != null) {
    await db.songLinks.insert().insert(
      SongLinksCompanion.insert(
        sourceUuid: uuid,
        type: SongLinkType.localCopyOf,
        targetUuid: origin.bankSongUuid,
        targetContentHash: Value(origin.bankContentHash),
      ),
    );
  }
}

Future<void> _writeCheckpoints(String uuid, List<String> checkpoints) =>
    (db.songs.update()..where((s) => s.uuid.equals(uuid))).write(
      SongsCompanion(checkpoints: Value(checkpoints)),
    );

/// Makes [mine] (keeping its uuid, bank, variationOf and links) carry the
/// incoming content and attachments, and merges the checkpoints.
Future<void> _replaceContent(Song mine, BundledSong incoming) async {
  final song = incoming.song;
  await (db.songs.update()..where((s) => s.uuid.equals(mine.uuid))).write(
    SongsCompanion(
      title: Value(song.title),
      lyrics: Value(song.lyrics),
      lyricsFormat: Value(song.lyricsFormat),
      keyField: Value(song.keyField),
      contentMap: Value(song.contentMap),
      checkpoints: Value(
        _mergeCheckpoints(
          mine.checkpoints,
          song.checkpoints,
          incoming.contentHash,
        ),
      ),
    ),
  );
  for (final field in assetFieldExtensions.keys) {
    final bytes = incoming.assets[field];
    if (bytes != null) {
      await putLocalAssetRow(mine.uuid, field, bytes);
    } else {
      await db.assets.deleteWhere(
        (a) => a.songUuid.equals(mine.uuid) & a.fieldName.equals(field),
      );
    }
  }
}

Future<BundleCueResult> _applyCue(
  Map<String, dynamic> cueJson,
  Map<String, String> remap,
  CueImportChoice choice,
) async {
  final json = Map<String, dynamic>.from(cueJson);
  json['content'] = [
    for (final slide in (json['content'] as List).cast<Map>())
      _remapSlide(slide, remap),
  ];

  final uuid = json['uuid'] as String;
  final existing = await (db.cues.select()..where((c) => c.uuid.equals(uuid)))
      .getSingleOrNull();
  if (existing == null) {
    return BundleCueResult(
      await insertCueFromJson(json: json),
      CueImportAction.created,
    );
  }
  switch (choice) {
    case CueImportChoice.overwrite:
      return BundleCueResult(
        await overwriteCueRowFromJson(json),
        CueImportAction.overwritten,
      );
    case CueImportChoice.keepBoth:
      json['uuid'] = UuidV4().generate();
      return BundleCueResult(
        await insertCueFromJson(json: json),
        CueImportAction.createdCopy,
      );
    case CueImportChoice.skip:
      return BundleCueResult(existing, CueImportAction.skipped);
  }
}

Map _remapSlide(Map slide, Map<String, String> remap) {
  final copy = Map<String, dynamic>.from(slide);
  final song = copy['song'];
  if (copy['slideType'] == 'song' && song is Map) {
    final target = remap[song['uuid']];
    if (target != null) copy['song'] = {...song, 'uuid': target};
  }
  return copy;
}
