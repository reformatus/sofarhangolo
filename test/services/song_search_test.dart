import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/filter.dart';
import 'package:sofarhangolo/ui/base/songs/widgets/filter/types/key/state.dart';

/// End-to-end coverage of the registry-driven search query, which had none
/// before (the bug this guards against: resolving hits to typed songs through
/// an API that requires drift-generated table metadata).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LyricDatabase testDb;

  const noKeyFilters = (
    pitches: <String>{},
    modes: <String>{},
    keys: <KeyField>{},
  );

  setUp(() async {
    testDb = LyricDatabase(NativeDatabase.memory());
    db = testDb;
    await db.ensureSearchIndex();
  });

  tearDown(() async {
    await testDb.close();
  });

  Song songWith(
    String uuid,
    String title, {
    String? lyrics,
    Map<String, Object> contentMap = const {},
    List<KeyField> keyField = const [],
  }) => Song(
    uuid: uuid,
    title: title,
    lyrics: lyrics,
    keyField: keyField,
    contentMap: contentMap,
  );

  Future<List<SongResult>> search(
    String term, {
    List<String> fields = const [],
    int limit = 50,
  }) {
    return searchSongs(
      searchString: term,
      searchFields: fields,
      filters: const {},
      bankFilters: const {},
      keyFilters: noKeyFilters,
      limit: limit,
    ).first;
  }

  test('whole-value matches rank above substring matches', () async {
    await db.batch(
      (batch) => batch.insertAll(db.songs, [
        songWith('substring', 'Találj meg engem'),
        songWith('exact', 'Másik dal', contentMap: {'composer': 'Találj'}),
      ]),
    );

    final results = await search('talalj');

    // The composer is the term exactly (tier 0), the title only contains it.
    expect(results.map((r) => r.song.uuid).toList(), ['exact', 'substring']);
    expect(results[0].match?.tier, 0);
    expect(results[1].match?.tier, 1);
  });

  test('substring hits rank by field group', () async {
    await db.batch(
      (batch) => batch.insertAll(db.songs, [
        songWith('title-hit', 'Találj meg engem'),
        songWith(
          'people-hit',
          'Másik dal',
          contentMap: {'composer': 'Találj meg'},
        ),
        songWith('lyrics-hit', 'Harmadik', lyrics: 'találj a szövegben'),
      ]),
    );

    final results = await search('talalj');

    // title (10) > people (5) > lyrics (1)
    expect(results.map((r) => r.song.uuid).toList(), [
      'title-hit',
      'people-hit',
      'lyrics-hit',
    ]);
  });

  test('folds accents for exact and substring matching', () async {
    await db.into(db.songs).insert(songWith('acc', 'Áldál téged'));

    // Folded, the whole title equals the term (tier 0).
    final results = await search('aldal');

    expect(results.map((r) => r.song.uuid).toList(), ['acc']);
  });

  test('falls back to substring matching below the trigram minimum', () async {
    await db.batch(
      (batch) => batch.insertAll(db.songs, [
        songWith('short', 'Az Úr'),
        songWith('unrelated', 'Másik dal'),
      ]),
    );

    // Two characters: the trigram index cannot match, LIKE still must.
    final results = await search('Úr');

    expect(results.map((r) => r.song.uuid).toList(), ['short']);
    // Substring tier, and no FTS hit to rank by.
    expect(results.single.match?.tier, 1);
    expect(results.single.match?.rank, 0);
    // LIKE hits highlight the match too, not just FTS ones.
    expect(results.single.match?.matchTitle, 'Az <?Úr?>');
  });

  test('reports per-field snippets with the highlight tags', () async {
    await db.batch(
      (batch) => batch.insertAll(db.songs, [
        songWith('title-hit', 'Találj meg engem'),
        songWith('people-hit', 'Másik dal', contentMap: {'composer': 'Találj'}),
      ]),
    );

    final results = await search('talalj');
    final byUuid = {for (final r in results) r.song.uuid: r.match};

    expect(byUuid['title-hit']?.matchTitle, contains('<?'));
    expect(byUuid['title-hit']?.matches['composer'], isNull);
    expect(byUuid['people-hit']?.matches['composer'], contains('<?'));
  });

  test('restricts the match to the selected fields', () async {
    await db.batch(
      (batch) => batch.insertAll(db.songs, [
        songWith('title-hit', 'Találj meg engem'),
        songWith('people-hit', 'Másik dal', contentMap: {'composer': 'Találj'}),
      ]),
    );

    final results = await search('talalj', fields: ['composer']);

    expect(results.map((r) => r.song.uuid).toList(), ['people-hit']);
  });

  test('limits results and pages stably', () async {
    await db.batch(
      (batch) => batch.insertAll(db.songs, [
        songWith('first', 'Találj meg'),
        songWith('second', 'Találj velem'),
        songWith('third', 'Találj értem'),
      ]),
    );

    final firstPage = await search('talalj', limit: 2);
    expect(firstPage, hasLength(2));

    final all = await search('talalj', limit: 10);
    expect(all, hasLength(3));
    // The page is a prefix of the full, deterministically ordered result.
    expect(
      firstPage.map((r) => r.song.uuid),
      all.take(2).map((r) => r.song.uuid),
    );
  });

  Future<int> count({
    String term = '',
    Map<String, List<String>> filters = const {},
    KeyFilters keyFilters = noKeyFilters,
  }) {
    return countSongs(
      searchString: term,
      searchFields: const [],
      filters: filters,
      bankFilters: const {},
      keyFilters: keyFilters,
    ).first;
  }

  test('counts every match, independently of the pagination limit', () async {
    await db.batch(
      (batch) => batch.insertAll(db.songs, [
        songWith('a', 'Találj meg'),
        songWith('b', 'Találj velem'),
        songWith('c', 'Találj értem'),
        songWith('d', 'Másik dal'),
      ]),
    );

    // The list may be paginated down to fewer results than exist.
    expect(await search('talalj', limit: 2), hasLength(2));
    expect(await count(term: 'talalj'), 3);
    expect(await count(), 4);
  });

  test('counts respect the key filter', () async {
    await db.batch(
      (batch) => batch.insertAll(db.songs, [
        songWith('c-major', 'Első', keyField: [KeyField('C', 'dúr')]),
        songWith('d-major', 'Második', keyField: [KeyField('D', 'dúr')]),
      ]),
    );

    expect(await count(), 2);
    expect(await count(keyFilters: (pitches: {'C'}, modes: {}, keys: {})), 1);
  });

  test('returns typed songs with their assets', () async {
    await db.into(db.songs).insert(songWith('a', 'Találj meg'));

    final results = await search('talalj');

    expect(results.single.song.title, 'Találj meg');
    expect(results.single.downloadedAssets, isEmpty);
  });

  test('the key filter applies in the search path too', () async {
    await db.batch(
      (batch) => batch.insertAll(db.songs, [
        songWith('c-major', 'Találj meg', keyField: [KeyField('C', 'dúr')]),
        songWith('a-minor', 'Találj velem', keyField: [KeyField('A', 'moll')]),
        songWith('no-key', 'Találj értem'),
      ]),
    );

    Future<Set<String>> uuids(KeyFilters keyFilters) => searchSongs(
      searchString: 'talalj',
      searchFields: const [],
      filters: const {},
      bankFilters: const {},
      keyFilters: keyFilters,
      limit: 50,
    ).first.then((results) => results.map((r) => r.song.uuid).toSet());

    expect(await uuids(noKeyFilters), {'c-major', 'a-minor', 'no-key'});
    expect(
      await uuids((pitches: {'C'}, modes: <String>{}, keys: <KeyField>{})),
      {'c-major'},
    );
    expect(await uuids((pitches: {'A'}, modes: {'moll'}, keys: <KeyField>{})), {
      'a-minor',
    });
    expect(
      await uuids((
        pitches: <String>{},
        modes: <String>{},
        keys: {KeyField('C', 'dúr')},
      )),
      {'c-major'},
    );
  });
}
