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
  SongFieldOwnership? ownership,
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

SongFieldOwnership _owns({
  Iterable<String> content = const [],
  bool keyField = false,
  bool lyrics = false,
}) {
  return SongFieldOwnership(
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

  group('resolveVariationChain', () {
    Future<Song?> Function(String) loaderOf(Map<String, Song> songs) {
      return (uuid) async => songs[uuid];
    }

    test('merges a single-level variation against its parent', () async {
      final parent = _fullParent();
      final own = _song('own', variationOf: 'parent', ownership: _owns());
      final db = {'own': own, 'parent': parent};

      final (resolved, error) = await resolveVariationChain(own, loaderOf(db));

      expect(error, isNull);
      expect(resolved.lyrics, 'parent lyrics');
      expect(resolved.keyField, parent.keyField);
      expect(resolved.contentMap['svg'], 'parent-svg');
      expect(resolved.variationOf, 'parent');
    });

    test('already-merged songs resolve to their stored content', () async {
      final parent = _fullParent();
      final own = _song(
        'own',
        variationOf: 'parent',
        lyrics: 'parent lyrics',
        keyField: parent.keyField,
        contentMap: {'lyrics': 'parent-lyrics', 'svg': 'parent-svg'},
        ownership: _owns(),
      );
      final db = {'own': own, 'parent': parent};

      final (resolved, error) = await resolveVariationChain(own, loaderOf(db));

      expect(error, isNull);
      expect(resolved.sameMergeableContentAs(own), isTrue);
    });

    test('missing parent keeps the stored song and reports no error', () async {
      final own = _song('own', variationOf: 'ghost', ownership: _owns());

      final (resolved, error) = await resolveVariationChain(own, loaderOf({}));

      expect(error, isNull);
      expect(identical(resolved, own), isTrue);
    });

    test('inherits through multi-level chains from the chain root', () async {
      final grandParent = _fullParent(uuid: 'grandparent');
      final parent = _song(
        'parent',
        variationOf: 'grandparent',
        ownership: _owns(),
      );
      final child = _song('child', variationOf: 'parent', ownership: _owns());
      final db = {'child': child, 'parent': parent, 'grandparent': grandParent};

      final (resolved, error) = await resolveVariationChain(
        child,
        loaderOf(db),
      );

      expect(error, isNull);
      expect(resolved.lyrics, 'parent lyrics');
      expect(resolved.keyField, grandParent.keyField);
      expect(resolved.contentMap['svg'], 'parent-svg');
    });

    test('reports cyclic chains on the node closing the cycle', () async {
      final a = _song('a', variationOf: 'b', ownership: _owns());
      final b = _song('b', variationOf: 'a', ownership: _owns());
      final db = {'a': a, 'b': b};

      final (resolved, error) = await resolveVariationChain(a, loaderOf(db));

      expect(error, isNotNull);
      expect(error!.kind, VariationMergeErrorKind.cyclicChain);
      expect(error.song.uuid, 'b');
      expect(identical(resolved, a), isTrue);
    });

    test('reports self-referencing variations', () async {
      final a = _song('a', variationOf: 'a', ownership: _owns());

      final (resolved, error) = await resolveVariationChain(
        a,
        loaderOf({'a': a}),
      );

      expect(error, isNotNull);
      expect(error!.kind, VariationMergeErrorKind.cyclicChain);
      expect(error.song.uuid, 'a');
      expect(identical(resolved, a), isTrue);
    });

    test('reports over-deep chains on the first node past the cap', () async {
      final root = _fullParent(uuid: 'song-10');
      final songs = <String, Song>{'song-10': root};
      for (var i = 9; i >= 0; i--) {
        songs['song-$i'] = _song(
          'song-$i',
          variationOf: 'song-${i + 1}',
          ownership: _owns(),
        );
      }

      final (resolved, error) = await resolveVariationChain(
        songs['song-0']!,
        loaderOf(songs),
        maxDepth: 5,
      );

      expect(error, isNotNull);
      expect(error!.kind, VariationMergeErrorKind.tooDeep);
      expect(error.song.uuid, 'song-5');
      expect(identical(resolved, songs['song-0']), isTrue);
    });

    test('chains up to the depth cap resolve without error', () async {
      final root = _fullParent(uuid: 'song-4');
      final songs = <String, Song>{'song-4': root};
      for (var i = 3; i >= 0; i--) {
        songs['song-$i'] = _song(
          'song-$i',
          variationOf: 'song-${i + 1}',
          ownership: _owns(),
        );
      }

      final (resolved, error) = await resolveVariationChain(
        songs['song-0']!,
        loaderOf(songs),
        maxDepth: 5,
      );

      expect(error, isNull);
      expect(resolved.lyrics, 'parent lyrics');
      expect(resolved.contentMap['svg'], 'parent-svg');
    });

    test(
      'frozen ancestors cut the chain, children merge from stored values',
      () async {
        final grandParent = _fullParent(uuid: 'grandparent');
        final frozenParent = _song(
          'parent',
          variationOf: 'grandparent',
          lyrics: 'frozen lyrics',
          ownership: null,
        );
        final child = _song('child', variationOf: 'parent', ownership: _owns());
        final db = {
          'child': child,
          'parent': frozenParent,
          'grandparent': grandParent,
        };

        final (resolved, error) = await resolveVariationChain(
          child,
          loaderOf(db),
        );

        expect(error, isNull);
        expect(resolved.lyrics, 'frozen lyrics');
        // The frozen parent was never re-merged itself, so its stored row
        // (without 'svg') is what the child inherits from; grandparent values
        // do not pass through the frozen node.
        expect(resolved.contentMap.containsKey('svg'), isFalse);
      },
    );

    test('songs without ownership metadata stay frozen', () async {
      final parent = _fullParent();
      final own = _song('own', variationOf: 'parent', lyrics: 'old lyrics');
      final db = {'own': own, 'parent': parent};

      final (resolved, error) = await resolveVariationChain(own, loaderOf(db));

      expect(error, isNull);
      expect(identical(resolved, own), isTrue);
      expect(resolved.lyrics, 'old lyrics');
    });
  });
}
