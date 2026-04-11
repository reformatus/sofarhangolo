import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/cue/write_cue.dart';
import 'package:sofarhangolo/ui/cue/session/session_provider.dart';

import '../../harness/test_harness.dart';

void main() {
  group('updateCueFromJson', () {
    late LyricDatabase testDb;
    late TestHarness harness;

    setUp(() async {
      testDb = createTestDatabase();
      db = testDb;
      await db.customStatement('PRAGMA foreign_keys = OFF');
      harness = TestHarness();
    });

    tearDown(() async {
      harness.dispose();
      await testDb.close();
    });

    Future<Cue> insertCue({
      required String uuid,
      required String title,
      required String description,
      required List<Map<String, dynamic>> content,
    }) {
      return db
          .into(db.cues)
          .insertReturning(
            CuesCompanion(
              id: const Value.absent(),
              uuid: Value(uuid),
              title: Value(title),
              description: Value(description),
              cueVersion: Value(currentCueVersion),
              content: Value(content),
            ),
          );
    }

    Future<void> insertSong({
      required String uuid,
      required String title,
    }) async {
      await db
          .into(db.songs)
          .insert(
            Song.fromBankApiJson({
              'uuid': uuid,
              'title': title,
              'lyrics': '<song><lyrics>$title</lyrics></song>',
              'lyricsFormat': 'opensong',
            }),
            mode: InsertMode.insertOrReplace,
          );
    }

    test(
      'updates the currently open cue session by reloading it from the database',
      () async {
        final cue = await insertCue(
          uuid: 'cue-1',
          title: 'Old title',
          description: 'Old description',
          content: [
            {'slideType': 'unknown', 'uuid': 'slide-1', 'comment': null},
          ],
        );

        await harness.container
            .read(activeCueSessionProvider.notifier)
            .load(cue.uuid);

        final before = harness.container.read(activeCueSessionProvider).value!;

        final updatedCue = await updateCueFromJson(
          json: {
            'uuid': cue.uuid,
            'title': 'New title',
            'description': 'New description',
            'cueVersion': currentCueVersion,
            'content': [
              {'slideType': 'unknown', 'uuid': 'slide-2', 'comment': null},
            ],
          },
          container: harness.container,
        );

        final after = harness.container.read(activeCueSessionProvider).value!;
        final storedCue = await (db.select(
          db.cues,
        )..where((c) => c.uuid.equals(cue.uuid))).getSingle();

        expect(updatedCue, isNot(same(before.cue)));
        expect(after.cue, same(updatedCue));
        expect(after.cue.title, 'New title');
        expect(after.cue.description, 'New description');
        expect(after.slides.map((slide) => slide.uuid).toList(), ['slide-2']);
        expect(after.currentSlideUuid, 'slide-2');

        expect(storedCue.title, 'New title');
        expect(storedCue.description, 'New description');
        expect(storedCue.content.map((slide) => slide['uuid']).toList(), [
          'slide-2',
        ]);
      },
    );

    test(
      'reopens an updated cue from db for nested song slide payloads',
      () async {
        await insertSong(uuid: 'song-1', title: 'Imported Song');
        final cue = await insertCue(
          uuid: 'cue-1',
          title: 'Old title',
          description: 'Old description',
          content: [
            {'slideType': 'unknown', 'uuid': 'slide-1', 'comment': null},
          ],
        );

        await harness.container
            .read(activeCueSessionProvider.notifier)
            .load(cue.uuid);

        final updatedCue = await updateCueFromJson(
          json: {
            'uuid': cue.uuid,
            'title': 'Song cue',
            'description': 'Imported description',
            'cueVersion': currentCueVersion,
            'content': [
              {
                'slideType': 'song',
                'uuid': 'slide-song',
                'song': <dynamic, dynamic>{
                  'uuid': 'song-1',
                  'contentHash': '123',
                },
                'viewType': 'lyrics',
                'transpose': <dynamic, dynamic>{'semitones': 1, 'capo': 2},
              },
            ],
          },
          container: harness.container,
        );

        final after = harness.container.read(activeCueSessionProvider).value!;
        final slide = after.slides.single;

        expect(updatedCue, same(after.cue));
        expect(after.cue.title, 'Song cue');
        expect(slide.uuid, 'slide-song');
        expect(slide.toJson()['song']['uuid'], 'song-1');
        expect(after.cue.content.single['song']['uuid'], 'song-1');
      },
    );
  });
}
