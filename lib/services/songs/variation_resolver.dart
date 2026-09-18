import '../../data/song/extensions.dart';
import '../../data/song/song.dart';

/// Maximum number of songs followed upwards in a variation chain before
/// giving up, guarding against pathologically deep (or cyclic) upstream data.
const defaultMaxVariationDepth = 5;

/// Merges a variation song with its (already updated) parent: empty own
/// fields are filled from the parent, non-empty own fields are kept.
Song resolveVariation({required Song own, required Song parent}) {
  return Song(
    contentMap: parent.contentMap.map((key, parentValue) {
      final ownValue = own.contentMap[key];
      if (ownValue != null && ownValue.isNotEmpty) {
        return MapEntry(key, ownValue);
      } else {
        return MapEntry(key, parentValue);
      }
    }),
    keyField: own.keyField.isNotEmpty ? own.keyField : parent.keyField,
    title: own.title,
    uuid: own.uuid,
    lyrics: own.hasLyrics ? own.lyrics : parent.lyrics,
    lyricsFormat: own.lyricsFormat,
    sourceBank: own.sourceBank,
    variationOf: own.variationOf,
  );
}

/// Walks up the variation chain starting from [song], following
/// [lookupParent] links. Returns the chain ordered child-first, or null when
/// the chain cannot be resolved because it is cyclic or deeper than
/// [maxDepth].
Future<List<Song>?> resolveVariationChain({
  required Song song,
  required Future<Song?> Function(String uuid) lookupParent,
  int maxDepth = defaultMaxVariationDepth,
}) async {
  final chain = <Song>[song];
  final visited = <String>{song.uuid};
  var current = song;

  while (current.variationOf != null) {
    if (chain.length >= maxDepth) {
      return null;
    }

    final parent = await lookupParent(current.variationOf!);
    if (parent == null) break;
    if (!visited.add(parent.uuid)) return null;

    chain.add(parent);
    current = parent;
  }

  return chain;
}
