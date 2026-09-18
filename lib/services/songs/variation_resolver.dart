import '../../data/song/song.dart';

/// Maximum number of songs followed upwards in a variation chain before
/// giving up, guarding against pathologically deep (or cyclic) upstream data.
const defaultMaxVariationDepth = 5;

/// Why a variation chain could not be fully resolved.
enum VariationMergeErrorKind {
  /// A [Song.variationOf] cycle was encountered.
  cyclicChain,

  /// The chain is deeper than [defaultMaxVariationDepth].
  tooDeep,
}

/// A variation chain that could not be fully resolved locally.
class VariationMergeError {
  final VariationMergeErrorKind kind;

  /// The song whose [Song.variationOf] could not be followed.
  final Song song;

  const VariationMergeError({required this.kind, required this.song});

  @override
  String toString() => '${kind.name}: ${song.uuid} (${song.title})';
}

/// Result of a full local variation re-merge.
class VariationMergeResult {
  /// Songs whose stored row differs from the re-merged output. These are the
  /// only songs that need to be written back.
  final List<Song> songsToWrite;

  /// Chains that could not be fully resolved.
  final List<VariationMergeError> errors;

  const VariationMergeResult({
    required this.songsToWrite,
    required this.errors,
  });
}

/// Merges a variation song with its parent using [Song.ownership] metadata:
/// fields the song owns are kept as stored, everything else is inherited from
/// the parent.
///
/// Songs without ownership metadata (legacy rows) are frozen and returned
/// unchanged.
Song resolveVariation({required Song own, required Song parent}) {
  final ownership = own.ownership;
  if (ownership == null) return own;

  final mergedContentMap = <String, String>{};
  for (final key in {...parent.contentMap.keys, ...ownership.contentKeys}) {
    if (ownership.contentKeys.contains(key)) {
      // Owned values live in the stored row; the parent fallback only exists
      // to keep the merge total if that invariant was broken.
      mergedContentMap[key] =
          own.contentMap[key] ?? parent.contentMap[key] ?? '';
    } else {
      final parentValue = parent.contentMap[key];
      if (parentValue != null) mergedContentMap[key] = parentValue;
    }
  }

  return Song(
    contentMap: mergedContentMap,
    keyField: ownership.keyField ? own.keyField : parent.keyField,
    title: own.title,
    uuid: own.uuid,
    lyrics: ownership.lyrics ? own.lyrics : parent.lyrics,
    lyricsFormat: own.lyricsFormat,
    sourceBank: own.sourceBank,
    variationOf: own.variationOf,
    ownership: ownership,
  );
}

/// Recomputes the merged content of every variation chain in [allSongs]
/// locally, without any API access.
///
/// Every song's merged output is computed exactly once and memoized. Chains
/// that cannot be resolved (cyclic or deeper than [maxDepth]) are reported in
/// [VariationMergeResult.errors]; the affected songs resolve to their stored
/// version so everything else still merges deterministically. A
/// [Song.variationOf] pointing outside [allSongs] keeps the child unchanged.
///
/// Only songs whose re-merged output differs from their stored row end up in
/// [VariationMergeResult.songsToWrite].
VariationMergeResult mergeAllVariations(
  Iterable<Song> allSongs, {
  int maxDepth = defaultMaxVariationDepth,
}) {
  final byUuid = {for (final song in allSongs) song.uuid: song};
  final resolved = <String, Song>{};
  final errors = <VariationMergeError>[];
  final inProgress = <String>{};

  Song resolve(String uuid, int depth) {
    final cached = resolved[uuid];
    if (cached != null) return cached;

    final own = byUuid[uuid]!;
    inProgress.add(uuid);
    final Song result;
    try {
      final parentUuid = own.variationOf;
      if (parentUuid == null) {
        result = own;
      } else if (inProgress.contains(parentUuid)) {
        errors.add(
          VariationMergeError(
            kind: VariationMergeErrorKind.cyclicChain,
            song: own,
          ),
        );
        result = own;
      } else if (depth >= maxDepth) {
        errors.add(
          VariationMergeError(kind: VariationMergeErrorKind.tooDeep, song: own),
        );
        result = own;
      } else {
        final parent = byUuid[parentUuid];
        if (parent == null) {
          result = own;
        } else {
          result = resolveVariation(
            own: own,
            parent: resolve(parentUuid, depth + 1),
          );
        }
      }
    } finally {
      inProgress.remove(uuid);
    }
    return resolved[uuid] = result;
  }

  for (final uuid in byUuid.keys) {
    resolve(uuid, 0);
  }

  final songsToWrite = <Song>[];
  for (final song in byUuid.values) {
    if (song.variationOf == null) continue;
    if (!resolved[song.uuid]!.sameMergeableContentAs(song)) {
      songsToWrite.add(resolved[song.uuid]!);
    }
  }

  return VariationMergeResult(songsToWrite: songsToWrite, errors: errors);
}
