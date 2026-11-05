import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/song/from_uuid.dart';
import 'package:sofarhangolo/services/songs/write_song.dart';
import 'package:sofarhangolo/ui/song/edit/autosave_indicator.dart';
import 'package:sofarhangolo/ui/song/edit/editor_controller.dart';

import '../../../harness/test_harness.dart';

void main() {
  late LyricDatabase testDb;
  late ProviderContainer container;
  late Song song;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    container = ProviderContainer();
    song = await createLocalSong(Song.local(title: 'Eredeti'));
  });

  tearDown(() async {
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await testDb.close();
  });

  /// Loads the controller and keeps it alive (as the mounted page does).
  Future<LocalSongEditorController> open() async {
    final provider = localSongEditorControllerProvider(song.uuid);
    container.listen(provider, (_, _) {});
    await container.read(provider.future);
    return container.read(provider.notifier);
  }

  LocalSongEditorState current() =>
      container.read(localSongEditorControllerProvider(song.uuid)).requireValue;

  Future<void> until(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (!condition()) {
      if (stopwatch.elapsed > timeout) fail('Timed out waiting for condition');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> untilStored(bool Function(Song? stored) condition) async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      if (condition(await dbSongFromUuid(song.uuid))) return;
      if (stopwatch.elapsed > const Duration(seconds: 5)) {
        fail('Timed out waiting for the stored song');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Holds the database busy so a save that starts meanwhile stays in flight
  /// until [release] is called.
  ({void Function() release, Future<void> done}) blockDatabase() {
    final gate = Completer<void>();
    final started = Completer<void>();
    final done = db.transaction(() async {
      started.complete();
      await gate.future;
    });
    return (release: gate.complete, done: done);
  }

  test('edits are debounced into one write: saving, saved, upToDate', () async {
    final controller = await open();
    var writes = 0;
    final subscription = db
        .select(db.songs)
        .watch()
        .skip(1)
        .listen((_) => writes++);
    addTearDown(subscription.cancel);

    controller
      ..setTitle('a')
      ..setTitle('ab')
      ..setTitle('abc');
    expect(current().status, AutosaveStatus.saving);

    await until(() => current().status == AutosaveStatus.saved);
    expect((await dbSongFromUuid(song.uuid))!.title, 'abc');
    expect(current().song.title, 'abc');
    expect(writes, 1);

    await until(() => current().status == AutosaveStatus.upToDate);
    expect(writes, 1);
  });

  test('writes never overlap and the last draft wins', () async {
    final controller = await open();

    final block = blockDatabase();
    controller.setTitle('eleje');
    // The debounce fires and the save starts, stuck behind the busy database.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    controller.setTitle('kozepe');
    controller.setLyrics('<song><lyrics>vege</lyrics></song>');
    expect(current().status, AutosaveStatus.saving);

    block.release();
    await block.done;
    await until(() => current().status == AutosaveStatus.saved);

    final stored = (await dbSongFromUuid(song.uuid))!;
    expect(stored.title, 'kozepe');
    expect(stored.lyrics, '<song><lyrics>vege</lyrics></song>');
    expect(current().draft.title, 'kozepe');
  });

  test('an edit during an in-flight save keeps the status saving', () async {
    final controller = await open();

    final block = blockDatabase();
    controller.setTitle('egy');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    controller.setTitle('ketto');
    block.release();
    await block.done;

    // The first save finishes but is already outdated: never "saved" for it.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(current().status, AutosaveStatus.saving);

    await until(() => current().status == AutosaveStatus.saved);
    expect((await dbSongFromUuid(song.uuid))!.title, 'ketto');
  });

  test(
    'attachments survive later edits; removed ones are not restored',
    () async {
      final controller = await open();

      await controller.attach('svg', Uint8List.fromList([1, 2, 3]));
      expect(current().song.contentMap['svg'], startsWith('local://'));
      final reference = current().song.contentMap['svg'];

      controller.setTitle('Új cím');
      await until(() => current().status == AutosaveStatus.saved);
      expect((await dbSongFromUuid(song.uuid))!.contentMap['svg'], reference);
      expect(current().song.contentMap['svg'], reference);
      expect(current().draft.contentMap['svg'], reference);

      await controller.removeAttachment('svg');
      expect(current().song.contentMap.containsKey('svg'), isFalse);

      controller.setTitle('Másik cím');
      await until(() => current().status == AutosaveStatus.saved);
      final stored = (await dbSongFromUuid(song.uuid))!;
      expect(stored.title, 'Másik cím');
      expect(stored.contentMap.containsKey('svg'), isFalse);
      expect(current().draft.contentMap.containsKey('svg'), isFalse);
    },
  );

  test('metadata: blank values clear the key', () async {
    final controller = await open();

    controller.setMetadataField('composer', 'Bach');
    expect(current().contentMap['composer'], 'Bach');
    controller.setMetadataField('composer', '  ');
    expect(current().contentMap.containsKey('composer'), isFalse);
  });

  test('deleting while a save is in flight leaves the song deleted', () async {
    final controller = await open();

    final block = blockDatabase();
    controller.setTitle('Mentés alatt');
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final deletion = controller.delete();
    expect(current().deleted, isTrue);
    controller.setTitle('Törlés után');
    block.release();
    await block.done;
    await deletion;

    expect(await dbSongFromUuid(song.uuid), isNull);
    expect(current().deleted, isTrue);
    expect(current().status, isNot(AutosaveStatus.error));
    expect(current().title, 'Mentés alatt');

    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(await dbSongFromUuid(song.uuid), isNull);
  });

  test('deleting with a pending debounce never writes the edit', () async {
    final controller = await open();

    controller.setTitle('Függőben');
    await controller.delete();
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(await dbSongFromUuid(song.uuid), isNull);
    expect(current().status, isNot(AutosaveStatus.error));
  });

  test('disposing with an unsaved edit still writes it', () async {
    final controller = await open();

    controller.setTitle('Elmentve kilépéskor');
    container.dispose();

    await untilStored((stored) => stored?.title == 'Elmentve kilépéskor');
  });

  test(
    'a song deleted elsewhere is treated as deleted, not resurrected',
    () async {
      final controller = await open();
      await deleteLocalSong(song);

      controller.setTitle('Szellem');
      await until(() => current().deleted);

      expect(current().status, isNot(AutosaveStatus.error));
      expect(await dbSongFromUuid(song.uuid), isNull);

      // Further edits are ignored.
      controller.setTitle('Még egy');
      expect(current().title, 'Szellem');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(await dbSongFromUuid(song.uuid), isNull);
    },
  );
}
