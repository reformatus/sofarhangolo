import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/lyrics/format.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/variation_resolver.dart';

Song _song(
  String uuid, {
  String? variationOf,
  String? title,
  String? lyrics,
  List<KeyField> keyField = const [],
  Map<String, String> contentMap = const {},
  LyricsFormat lyricsFormat = LyricsFormat.opensong,
  String? sourceBank,
  SongOwnership? ownership,
}) {
  return Song(
    uuid: uuid,
    title: title ?? 'Song $uuid',
    lyrics: lyrics,
    keyField: keyField,
    contentMap: Map.of(contentMap),
    lyricsFormat: lyricsFormat,
    sourceBank: sourceBank,
    variationOf: variationOf,
    ownership: ownership,
  );
}

SongOwnership _owns({
  Iterable<String> content = const [],
  bool keyField = false,
  bool lyrics = false,
}) {
  return SongOwnership(
    contentKeys: Set.of(content),
    keyField: keyField,
    lyrics: lyrics,
  );
}

/// A parent song with everything set, so children can inherit any field.
Song _fullParent({String uuid = 'parent', String? title}) {
  return _song(
    uuid,
    title: title,
    keyField: [KeyField('C', 'major')],
    lyrics: 'parent lyrics',
    contentMap: {'lyrics': 'parent-lyrics', 'svg': 'parent-svg'},
    ownership: _owns(content: ['lyrics', 'svg'], keyField: true, lyrics: true),
  );
}

void main() {
  group('resolveVariation', () {
    test('freezes songs without ownership metadata', () {
      final parent = _fullParent();
      final own = _song('own', variationOf: 'parent', lyrics: 'old lyrics');

      final merged = resolveVariation(own: own, parent: parent);

      expect(identical(merged, own), isTrue);
    });

    test('inherits unowned fields from parent', () {
      final parent = _fullParent();
      final own = _song('own', variationOf: 'parent', ownership: _owns());

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.keyField, [KeyField('C', 'major')]);
      expect(merged.lyrics, 'parent lyrics');
      expect(merged.contentMap, {
        'lyrics': 'parent-lyrics',
        'svg': 'parent-svg',
      });
    });

    test('keeps owned fields from the stored row', () {
      final parent = _fullParent();
      final own = _song(
        'own',
        variationOf: 'parent',
        keyField: [KeyField('G', 'major')],
        lyrics: 'own lyrics',
        contentMap: {'lyrics': 'own-lyrics'},
        ownership: _owns(content: ['lyrics'], keyField: true, lyrics: true),
      );

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.keyField, [KeyField('G', 'major')]);
      expect(merged.lyrics, 'own lyrics');
      expect(merged.contentMap['lyrics'], 'own-lyrics');
    });

    test('child-owned sections survive even when the parent lacks them', () {
      final parent = _fullParent();
      final own = _song(
        'own',
        variationOf: 'parent',
        contentMap: {'intro': 'own-intro'},
        ownership: _owns(content: ['intro']),
      );

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.contentMap, {
        'lyrics': 'parent-lyrics',
        'svg': 'parent-svg',
        'intro': 'own-intro',
      });
    });

    test('child sections absent from the ownership set are dropped', () {
      final parent = _fullParent();
      final own = _song(
        'own',
        variationOf: 'parent',
        contentMap: {'lyrics': 'own-lyrics', 'stale': 'own-stale'},
        ownership: _owns(content: ['lyrics']),
      );

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.contentMap, {'lyrics': 'own-lyrics', 'svg': 'parent-svg'});
    });

    test('keeps identity fields from own', () {
      final parent = _fullParent(title: 'Parent title', uuid: 'p2');
      final own = _song(
        'own',
        variationOf: 'p2',
        title: 'Own title',
        sourceBank: 'bank-2',
        ownership: _owns(),
      );

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.uuid, 'own');
      expect(merged.title, 'Own title');
      expect(merged.variationOf, 'p2');
      expect(merged.lyricsFormat, LyricsFormat.opensong);
      expect(merged.sourceBank, 'bank-2');
    });

    test('copies ownership metadata unchanged into the merged output', () {
      final parent = _fullParent();
      final ownership = _owns(content: ['lyrics'], lyrics: true);
      final own = _song('own', variationOf: 'parent', ownership: ownership);

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.ownership, ownership);
    });
  });

  group('mergeAllVariations', () {
    test('reports no writes when stored rows are already merged', () {
      final parent = _fullParent();
      final own = _song('own', variationOf: 'parent', ownership: _owns());
      final merged = resolveVariation(own: own, parent: parent);

      final result = mergeAllVariations([parent, merged]);

      expect(result.songsToWrite, isEmpty);
      expect(result.errors, isEmpty);
    });

    test('writes only the merged song when it differs from storage', () {
      final parent = _fullParent();
      final own = _song(
        'own',
        variationOf: 'parent',
        contentMap: {'lyrics': ''},
        lyrics: null,
        ownership: _owns(),
      );

      final result = mergeAllVariations([parent, own]);

      expect(result.songsToWrite, hasLength(1));
      expect(result.songsToWrite.single.uuid, 'own');
      expect(result.songsToWrite.single.lyrics, 'parent lyrics');
      expect(result.songsToWrite.single.contentMap, {
        'lyrics': 'parent-lyrics',
        'svg': 'parent-svg',
      });
    });

    test('never writes non-variation songs', () {
      final plain = _song('plain', lyrics: 'raw lyrics');

      final result = mergeAllVariations([plain]);

      expect(result.songsToWrite, isEmpty);
      expect(result.errors, isEmpty);
    });

    test('resolves multi-level chains', () {
      final grandParent = _fullParent(uuid: 'grand');
      final parent = _song(
        'parent',
        variationOf: 'grand',
        keyField: [KeyField('D', 'major')],
        ownership: _owns(keyField: true),
      );
      final child = _song(
        'child',
        variationOf: 'parent',
        contentMap: {'lyrics': ''},
        ownership: _owns(),
      );

      final result = mergeAllVariations([grandParent, parent, child]);

      expect(result.errors, isEmpty);
      expect(result.songsToWrite.map((s) => s.uuid).toSet(), {
        'parent',
        'child',
      });
      final mergedChild = result.songsToWrite.singleWhere(
        (s) => s.uuid == 'child',
      );
      expect(mergedChild.keyField, [KeyField('D', 'major')]);
      expect(mergedChild.lyrics, 'parent lyrics');
    });

    test('merges each chain node exactly once (no duplicate errors)', () {
      final a = _song('a', variationOf: 'b', ownership: _owns());
      final b = _song('b', variationOf: 'a', ownership: _owns());
      final c = _song('c', variationOf: 'b', ownership: _owns());

      final result = mergeAllVariations([a, b, c]);

      // The a<->b cycle is reachable from roots 'a', 'b' and 'c'; without
      // memoization it would be reported once per root. The error lands on
      // 'b', the node whose variationOf closes the cycle.
      expect(result.errors, hasLength(1));
      expect(result.errors.single.kind, VariationMergeErrorKind.cyclicChain);
      expect(result.errors.single.song.uuid, 'b');
    });

    test('reports cyclic chains as errors and keeps stored data', () {
      final a = _song(
        'a',
        variationOf: 'b',
        lyrics: 'a lyrics',
        ownership: _owns(lyrics: true),
      );
      final b = _song(
        'b',
        variationOf: 'a',
        lyrics: 'b lyrics',
        ownership: _owns(lyrics: true),
      );

      final result = mergeAllVariations([a, b]);

      expect(result.songsToWrite, isEmpty);
      expect(result.errors, hasLength(1));
      expect(result.errors.single.kind, VariationMergeErrorKind.cyclicChain);
      expect(result.errors.single.song.uuid, 'b');
    });

    test('reports self-referencing songs as cyclic', () {
      final a = _song('a', variationOf: 'a', ownership: _owns());

      final result = mergeAllVariations([a]);

      expect(result.errors, hasLength(1));
      expect(result.errors.single.kind, VariationMergeErrorKind.cyclicChain);
    });

    test('reports over-deep chains as errors', () {
      final songs = <Song>[
        for (var i = 0; i < 10; i++)
          _song('song-$i', variationOf: 'song-${i + 1}', ownership: _owns()),
        _song('song-10', ownership: _owns()),
      ];

      final result = mergeAllVariations(songs, maxDepth: 5);

      expect(
        result.errors.map((e) => e.kind),
        everyElement(VariationMergeErrorKind.tooDeep),
      );
      // Depths 0..4 resolve; 'song-5' is the first node past the cap.
      expect(result.errors.single.song.uuid, 'song-5');
    });

    test('resolves a chain of exactly maxDepth songs', () {
      final songs = <Song>[
        for (var i = 0; i < defaultMaxVariationDepth; i++)
          _song('song-$i', variationOf: 'song-${i + 1}', ownership: _owns()),
        _song('song-$defaultMaxVariationDepth', ownership: _owns()),
      ];

      final result = mergeAllVariations(songs);

      expect(result.errors, isEmpty);
      expect(result.songsToWrite, isEmpty);
    });

    test('keeps songs whose parent is missing from the bank data', () {
      final own = _song(
        'own',
        variationOf: 'missing',
        lyrics: 'own lyrics',
        ownership: _owns(lyrics: true),
      );

      final result = mergeAllVariations([own]);

      expect(result.errors, isEmpty);
      expect(result.songsToWrite, isEmpty);
    });

    test('merges against the stored parent when the parent is frozen', () {
      final parent = _fullParent();
      // Strip ownership from a copy to simulate a legacy row.
      final legacyParent = _song(
        'parent',
        keyField: [KeyField('C', 'major')],
        lyrics: 'parent lyrics',
        contentMap: {'lyrics': 'parent-lyrics', 'svg': 'parent-svg'},
      );
      final own = _song('own', variationOf: 'parent', ownership: _owns());

      final result = mergeAllVariations([legacyParent, own]);

      expect(result.errors, isEmpty);
      expect(result.songsToWrite.single.uuid, 'own');
      expect(result.songsToWrite.single.lyrics, 'parent lyrics');
      expect(parent, isNotNull);
    });
  });
}
