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

/// Result of resolving one variation chain.
typedef VariationChainResolution = (Song song, VariationMergeError? error);

/// Resolves the merged content of [own] by following its [Song.variationOf]
/// chain upwards, loading each ancestor with [loadParent].
///
/// Fields the song owns are kept as stored, everything else is inherited
/// from the chain root downwards (see [resolveVariation]). The walk stops
/// at the chain root, at an ancestor [loadParent] cannot provide, or at a
/// [Song] without ownership metadata (legacy rows are frozen and merged as
/// stored).
///
/// Chains that cannot be resolved are reported as the error part of the
/// result; the song part then falls back to its stored version so callers
/// can continue deterministically. Cycles are attributed to the node whose
/// variationOf closes the cycle, over-deep chains to the first node past
/// [maxDepth].
Future<VariationChainResolution> resolveVariationChain(
  Song own,
  Future<Song?> Function(String uuid) loadParent, {
  int maxDepth = defaultMaxVariationDepth,
}) async {
  final chain = <Song>[own];
  final visited = <String>{own.uuid};
  var current = own;

  while (current.variationOf != null) {
    final parentUuid = current.variationOf!;
    if (visited.contains(parentUuid)) {
      return (
        own,
        VariationMergeError(
          kind: VariationMergeErrorKind.cyclicChain,
          song: current,
        ),
      );
    }
    if (chain.length > maxDepth) {
      return (
        own,
        VariationMergeError(
          kind: VariationMergeErrorKind.tooDeep,
          song: current,
        ),
      );
    }
    final parent = await loadParent(parentUuid);
    if (parent == null) break;
    chain.add(parent);
    visited.add(parentUuid);
    current = parent;
  }

  var resolved = chain.last;
  for (var i = chain.length - 2; i >= 0; i--) {
    resolved = resolveVariation(own: chain[i], parent: resolved);
  }
  return (resolved, null);
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
