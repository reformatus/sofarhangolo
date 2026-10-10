import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/songs/filter.dart';

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
  }) => Song(
    uuid: uuid,
    title: title,
    lyrics: lyrics,
    keyField: const [],
    contentMap: contentMap,
  );

  Future<List<SongResult>> search(
    String term, {
    List<String> fields = const [],
  }) {
    return searchSongs(
      searchString: term,
      searchFields: fields,
      filters: const {},
      bankFilters: const {},
      keyFilters: noKeyFilters,
    ).first;
  }

  test('finds hits in every searchable field and ranks them by group', () async {
    await db.batch((batch) => batch.insertAll(db.songs, [
      songWith('title-hit', 'Találj meg engem'),
      songWith('people-hit', 'Másik dal', contentMap: {'composer': 'Találj'}),
      songWith('lyrics-hit', 'Harmadik', lyrics: 'találj a szövegben'),
    ]));

    final results = await search('talalj');

    // title (10) > people (5) > lyrics (1)
    expect(results.map((r) => r.song.uuid).toList(), [
      'title-hit',
      'people-hit',
      'lyrics-hit',
    ]);
  });

  test('reports per-field snippets with the highlight tags', () async {
    await db.batch((batch) => batch.insertAll(db.songs, [
      songWith('title-hit', 'Találj meg engem'),
      songWith('people-hit', 'Másik dal', contentMap: {'composer': 'Találj'}),
    ]));

    final results = await search('talalj');
    final byUuid = {for (final r in results) r.song.uuid: r.match};

    expect(byUuid['title-hit']?.matchTitle, contains('<?'));
    expect(byUuid['title-hit']?.snippets['composer'], isNull);
    expect(byUuid['people-hit']?.snippets['composer'], contains('<?'));
  });

  test('restricts the match to the selected fields', () async {
    await db.batch((batch) => batch.insertAll(db.songs, [
      songWith('title-hit', 'Találj meg engem'),
      songWith('people-hit', 'Másik dal', contentMap: {'composer': 'Találj'}),
    ]));

    final results = await search('talalj', fields: ['composer']);

    expect(results.map((r) => r.song.uuid).toList(), ['people-hit']);
  });

  test('returns typed songs with their assets', () async {
    await db.into(db.songs).insert(songWith('a', 'Találj meg'));

    final results = await search('talalj');

    expect(results.single.song.title, 'Találj meg');
    expect(results.single.downloadedAssets, isEmpty);
  });
}
