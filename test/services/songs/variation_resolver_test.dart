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
  );
}

void main() {
  group('resolveVariation', () {
    test('fills empty keyField from parent (key inheritance)', () {
      final parent = _song(
        'parent',
        keyField: [KeyField('C', 'major')],
        lyrics: 'parent lyrics',
      );
      final own = _song('own', variationOf: 'parent');

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.keyField, [KeyField('C', 'major')]);
    });

    test('keeps non-empty own keyField', () {
      final parent = _song('parent', keyField: [KeyField('C', 'major')]);
      final own = _song('own', keyField: [KeyField('G', 'major')]);

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.keyField, [KeyField('G', 'major')]);
    });

    test('fills empty own contentMap values from parent', () {
      final parent = _song(
        'parent',
        contentMap: {'lyrics': 'parent-lyrics', 'svg': 'parent-svg'},
      );
      final own = _song('own', contentMap: {'lyrics': '', 'svg': ''});

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.contentMap, {
        'lyrics': 'parent-lyrics',
        'svg': 'parent-svg',
      });
    });

    test('keeps non-empty own contentMap values', () {
      final parent = _song(
        'parent',
        contentMap: {'svg': 'parent-svg', 'pdf': 'parent-pdf'},
      );
      final own = _song('own', contentMap: {'svg': 'own-svg'});

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.contentMap, {'svg': 'own-svg', 'pdf': 'parent-pdf'});
    });

    test('fills missing lyrics from parent', () {
      final parent = _song('parent', lyrics: 'parent lyrics');
      final own = _song('own');

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.lyrics, 'parent lyrics');
    });

    test('keeps own lyrics when present', () {
      final parent = _song('parent', lyrics: 'parent lyrics');
      final own = _song('own', lyrics: 'own lyrics');

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.lyrics, 'own lyrics');
    });

    test('keeps identity fields from own', () {
      final parent = _song(
        'parent',
        title: 'Parent title',
        sourceBank: 'bank-1',
      );
      final own = _song(
        'own',
        variationOf: 'parent',
        title: 'Own title',
        sourceBank: 'bank-2',
      );

      final merged = resolveVariation(own: own, parent: parent);

      expect(merged.uuid, 'own');
      expect(merged.title, 'Own title');
      expect(merged.variationOf, 'parent');
      expect(merged.lyricsFormat, LyricsFormat.opensong);
      expect(merged.sourceBank, 'bank-2');
    });
  });

  group('resolveVariationChain', () {
    test('walks the parent chain child-first', () async {
      final songs = {
        'a': _song('a', variationOf: 'b'),
        'b': _song('b', variationOf: 'c'),
        'c': _song('c'),
      };

      final chain = await resolveVariationChain(
        song: songs['a']!,
        lookupParent: (uuid) async => songs[uuid],
      );

      expect(chain, isNotNull);
      expect(chain!.map((song) => song.uuid), ['a', 'b', 'c']);
    });

    test('stops at a missing parent', () async {
      final song = _song('a', variationOf: 'missing');

      final chain = await resolveVariationChain(
        song: song,
        lookupParent: (uuid) async => null,
      );

      expect(chain, isNotNull);
      expect(chain!.map((s) => s.uuid), ['a']);
    });

    test('terminates on a cyclic parent chain', () async {
      final songs = {
        'a': _song('a', variationOf: 'b'),
        'b': _song('b', variationOf: 'a'),
      };

      final chain = await resolveVariationChain(
        song: songs['a']!,
        lookupParent: (uuid) async => songs[uuid],
      );

      expect(chain, isNull);
    });

    test('terminates on a self-referencing song', () async {
      final song = _song('a', variationOf: 'a');

      final chain = await resolveVariationChain(
        song: song,
        lookupParent: (uuid) async => song,
      );

      expect(chain, isNull);
    });

    test('respects the depth cap', () async {
      final songs = {
        for (var i = 0; i < 10; i++)
          'song-$i': _song('song-$i', variationOf: 'song-${i + 1}'),
        'song-10': _song('song-10'),
      };
      Future<Song?> lookup(String uuid) async => songs[uuid];

      expect(
        await resolveVariationChain(
          song: songs['song-0']!,
          lookupParent: lookup,
          maxDepth: 5,
        ),
        isNull,
        reason: 'chain of 11 songs must not resolve with maxDepth 5',
      );

      final chain = await resolveVariationChain(
        song: songs['song-6']!,
        lookupParent: lookup,
        maxDepth: 5,
      );
      expect(chain, isNotNull);
      expect(chain, hasLength(5));
    });

    test('uses the default depth cap', () async {
      final songs = {
        for (var i = 0; i < defaultMaxVariationDepth; i++)
          'song-$i': _song('song-$i', variationOf: 'song-${i + 1}'),
        'song-$defaultMaxVariationDepth': _song(
          'song-$defaultMaxVariationDepth',
        ),
      };
      Future<Song?> lookup(String uuid) async => songs[uuid];

      final tooDeep = await resolveVariationChain(
        song: songs['song-0']!,
        lookupParent: lookup,
      );
      expect(tooDeep, isNull);

      final atCap = await resolveVariationChain(
        song: songs['song-1']!,
        lookupParent: lookup,
      );
      expect(atCap, isNotNull);
      expect(atCap, hasLength(defaultMaxVariationDepth));
    });
  });
}
