import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/song_link.dart';
import 'package:sofarhangolo/services/assets/write_song_asset.dart';
import 'package:sofarhangolo/services/songs/bundle/export_bundle.dart';
import 'package:sofarhangolo/services/songs/bundle/import_bundle.dart';
import 'package:sofarhangolo/services/songs/bundle/song_bundle.dart';
import 'package:sofarhangolo/services/songs/write_song.dart';

import '../../../harness/test_harness.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LyricDatabase deviceA;
  late LyricDatabase deviceB;

  Future<LyricDatabase> newDevice() async {
    final d = createTestDatabase();
    db = d;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db
        .into(db.banks)
        .insert(
          BanksCompanion.insert(
            uuid: 'bank-1',
            name: 'Test Bank',
            baseUrl: Value(Uri.parse('https://example.com/api')),
            parallelUpdateJobs: 1,
            amountOfSongsInRequest: 1,
            noCms: false,
            songFields: {},
            isEnabled: true,
            isOfflineMode: false,
          ),
        );
    return d;
  }

  setUp(() async {
    deviceA = await newDevice();
    deviceB = await newDevice();
    db = deviceA;
  });

  tearDown(() async {
    await deviceA.close();
    await deviceB.close();
  });

  Future<T> on<T>(LyricDatabase device, Future<T> Function() body) async {
    db = device;
    return body();
  }

  Future<Song> stored(String uuid) =>
      (db.songs.select()..where((s) => s.uuid.equals(uuid))).getSingle();

  Future<int> songCount() async => (await db.songs.select().get()).length;

  Future<Song> edit(String uuid, String lyrics) async {
    final s = await stored(uuid);
    return (await updateLocalSong(s.copyWith(lyrics: lyrics)))!;
  }

  Future<Song> newSong(String title, {String lyrics = 'v1'}) =>
      createLocalSong(Song.local(title: title, lyrics: lyrics));

  Future<ImportResult> import(
    Uint8List bytes, {
    Map<String, ImportChoice> choices = const {},
    CueImportChoice cueChoice = CueImportChoice.keepBoth,
  }) async {
    final plan = await planSongBundleImport(bytes);
    return applySongBundleImport(plan, choices, cueChoice: cueChoice);
  }

  Song bankSong(String uuid) => Song(
    uuid: uuid,
    title: 'Bank $uuid',
    lyrics: 'bank lyrics',
    keyField: const [],
    contentMap: {},
    sourceBank: 'bank-1',
  );

  Map<String, dynamic> cueJson(String uuid, List<String> songUuids) => {
    'uuid': uuid,
    'title': 'Lista',
    'description': 'leírás',
    'cueVersion': 1,
    'content': [
      for (final (i, s) in songUuids.indexed)
        {
          'uuid': 'slide-$i',
          'slideType': 'song',
          'song': {'uuid': s},
          'viewType': 'lyrics',
        },
    ],
  };

  Cue cueOf(Map<String, dynamic> json) => Cue(
    0,
    json['uuid'],
    json['title'],
    json['description'],
    json['cueVersion'],
    (json['content'] as List).cast<Map>(),
  );

  /// Rewrites a bundle's zip with [mutate] applied to its entries.
  Uint8List tamper(Uint8List bytes, Archive Function(Archive) mutate) =>
      Uint8List.fromList(
        ZipEncoder().encode(mutate(ZipDecoder().decodeBytes(bytes))),
      );

  Uint8List manifestBundle(Map<String, Object?> manifest) {
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))),
      );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  group('export / round trip', () {
    test(
      'round trips songs, attachments, origin and cue to a fresh DB',
      () async {
        final original = bankSong('bank-song');
        await db.into(db.songs).insert(original);
        final copy = await copySongToLocal(
          original,
          fetchAsset: (s, f) async => Uint8List.fromList([1, 2, 3]),
        );
        // copySongToLocal skips fields the song has no reference for.
        final withSvg = await writeLocalSongAsset(
          copy.uuid,
          'svg',
          Uint8List.fromList([9, 8, 7]),
        );
        final plain = await createLocalSong(
          Song.local(
            title: 'Másik',
            lyrics: 'x',
            keyField: [KeyField('C', 'dur'), KeyField('D', 'moll')],
            contentMap: {
              'composer': 'Bach',
              'genre': ['a', 'b'],
            },
          ),
        );
        // The same svg bytes on a second song: one bundle entry only.
        await writeLocalSongAsset(
          plain.uuid,
          'svg',
          Uint8List.fromList([9, 8, 7]),
        );

        final cue = cueOf(
          cueJson('cue-1', [withSvg.uuid, 'bank-song', plain.uuid]),
        );
        final bytes = await exportSongBundle([], cue: cue);

        final archive = ZipDecoder().decodeBytes(bytes);
        expect(
          archive.files
              .map((f) => f.name)
              .where((n) => n.startsWith('assets/')),
          [
            songBundleAssetPath(localAssetHash([9, 8, 7])),
          ],
        );

        final aHash = (await stored(plain.uuid)).contentHash;
        db = deviceB;
        final plan = await planSongBundleImport(bytes);
        expect(
          plan.songs.map((s) => s.outcome),
          everyElement(ImportOutcome.newSong),
        );
        expect(await songCount(), 0);
        final result = await applySongBundleImport(plan, {});
        expect(result.cue!.action, CueImportAction.created);
        expect(result.cue!.cue!.uuid, 'cue-1');

        final b = await stored(plain.uuid);
        expect(b.title, 'Másik');
        expect(b.keyField, [KeyField('C', 'dur'), KeyField('D', 'moll')]);
        expect(b.contentMap['genre'], ['a', 'b']);
        expect(b.sourceBank, localBankUuid);
        expect(b.contentHash, aHash);
        final assets = await db.assets.select().get();
        expect(assets, hasLength(2));
        final link =
            await (db.songLinks.select()
                  ..where((l) => l.sourceUuid.equals(withSvg.uuid)))
                .getSingle();
        expect(link.type, SongLinkType.localCopyOf);
        expect(link.targetUuid, 'bank-song');
        expect(link.targetContentHash, original.contentHash);
        // bank songs of the cue are not exported
        expect(await songCount(), 2);
      },
    );

    test('exported checkpoints include the current hash', () async {
      final s = await newSong('Cp');
      await edit(s.uuid, 'v2');
      final bytes = await exportSongBundle([s.uuid]);
      final bundle = readSongBundle(bytes);
      final current = (await stored(s.uuid)).contentHash;
      expect(bundle.songs.single.song.checkpoints.last, current);
      expect((await stored(s.uuid)).checkpoints.last, current);
    });

    test('skips bank songs and unknown uuids', () async {
      await db.into(db.songs).insert(bankSong('bs'));
      final bytes = await exportSongBundle(['bs', 'nope']);
      expect(readSongBundle(bytes).songs, isEmpty);
    });
  });

  group('receive rules', () {
    test('new song gets incoming checkpoints plus its hash', () async {
      final s = await newSong('N');
      final bytes = await exportSongBundle([s.uuid]);
      db = deviceB;
      final result = await import(bytes);
      expect(result.songs.single.action, ImportAction.created);
      final b = await stored(s.uuid);
      expect(b.checkpoints, [b.contentHash]);
    });

    test('identical', () async {
      final s = await newSong('Same');
      final bytes = await exportSongBundle([s.uuid]);
      final plan = await planSongBundleImport(bytes);
      expect(plan.songs.single.outcome, ImportOutcome.identical);
      final r = await applySongBundleImport(plan, {});
      expect(r.songs.single.action, ImportAction.unchanged);
    });

    test('ping-pong A->B, B edits, B->A is a fast-forward', () async {
      final s = await newSong('Pingpong');
      final toB = await exportSongBundle([s.uuid]);
      await on(deviceB, () async {
        await import(toB);
        await edit(s.uuid, 'B edit');
        return null;
      });
      final toA = await on(deviceB, () => exportSongBundle([s.uuid]));
      db = deviceA;
      final plan = await planSongBundleImport(toA);
      expect(plan.songs.single.outcome, ImportOutcome.fastForward);
      final r = await applySongBundleImport(plan, {});
      expect(r.songs.single.action, ImportAction.updated);
      final a = await stored(s.uuid);
      expect(a.lyrics, 'B edit');
      expect(a.checkpoints.last, a.contentHash);
      expect(a.checkpoints.toSet().length, a.checkpoints.length);
    });

    test('re-shared stale file changes nothing', () async {
      final s = await newSong('Stale');
      final v1 = await exportSongBundle([s.uuid]);
      await edit(s.uuid, 'v2');
      await exportSongBundle([s.uuid]);
      final before = await stored(s.uuid);

      final plan = await planSongBundleImport(v1);
      expect(plan.songs.single.outcome, ImportOutcome.stale);
      final r = await applySongBundleImport(plan, {});
      expect(r.songs.single.action, ImportAction.unchanged);
      final after = await stored(s.uuid);
      expect(after.lyrics, 'v2');
      expect(after.contentHash, before.contentHash);
    });

    Future<Uint8List> divergedBundle(Song s) async {
      // B receives v1, edits; A edits differently. Returns B's bundle.
      final toB = await exportSongBundle([s.uuid]);
      return on(deviceB, () async {
        await import(toB);
        await edit(s.uuid, 'B version');
        return exportSongBundle([s.uuid]);
      });
    }

    test('conflict + overwrite', () async {
      final s = await newSong('Konfliktus');
      final fromB = await divergedBundle(s);
      db = deviceA;
      await edit(s.uuid, 'A version');

      final plan = await planSongBundleImport(fromB);
      final p = plan.songs.single;
      expect(p.outcome, ImportOutcome.conflict);
      expect(p.choices, [ImportChoice.overwrite, ImportChoice.keepBoth]);
      expect(p.descendsFromOriginal, isFalse);
      final r = await applySongBundleImport(plan, {
        s.uuid: ImportChoice.overwrite,
      });
      expect(r.songs.single.action, ImportAction.updated);
      expect((await stored(s.uuid)).lyrics, 'B version');
      expect(await songCount(), 1);
    });

    test(
      'conflict + keepBoth makes a linked copy under a fresh uuid',
      () async {
        final s = await newSong('Konfliktus');
        final fromB = await divergedBundle(s);
        db = deviceA;
        await edit(s.uuid, 'A version');

        final r = await import(fromB, choices: {s.uuid: ImportChoice.keepBoth});
        final res = r.songs.single;
        expect(res.action, ImportAction.createdCopy);
        expect(res.resultingUuid, isNot(s.uuid));
        expect(r.uuidRemap, {s.uuid: res.resultingUuid});
        expect((await stored(s.uuid)).lyrics, 'A version');
        final copy = await stored(res.resultingUuid!);
        expect(copy.lyrics, 'B version');
        expect(copy.title, 'Konfliktus');
        expect(copy.checkpoints.last, copy.contentHash);
        final link =
            await (db.songLinks.select()
                  ..where((l) => l.sourceUuid.equals(copy.uuid)))
                .getSingle();
        expect(link.type, SongLinkType.importedCopyOf);
        expect(link.targetUuid, s.uuid);
      },
    );

    test('conflict flag: descends from the bank original only', () async {
      await db.into(db.songs).insert(bankSong('orig'));
      final copy = await copySongToLocal(bankSong('orig'));
      final toB = await exportSongBundle([copy.uuid]);
      final fromB = await on(deviceB, () async {
        await import(toB);
        await edit(copy.uuid, 'B');
        return exportSongBundle([copy.uuid]);
      });
      db = deviceA;
      await edit(copy.uuid, 'A');
      var plan = await planSongBundleImport(fromB);
      expect(plan.songs.single.outcome, ImportOutcome.conflict);
      expect(plan.songs.single.descendsFromOriginal, isTrue);

      // B now builds on a later version of mine: no longer "from original".
      final toB2 = await exportSongBundle([copy.uuid]);
      final fromB2 = await on(deviceB, () async {
        await import(toB2, choices: {copy.uuid: ImportChoice.overwrite});
        await edit(copy.uuid, 'B2');
        return exportSongBundle([copy.uuid]);
      });
      db = deviceA;
      await edit(copy.uuid, 'A2');
      plan = await planSongBundleImport(fromB2);
      expect(plan.songs.single.outcome, ImportOutcome.conflict);
      expect(plan.songs.single.descendsFromOriginal, isFalse);
    });

    test('uuid of a bank song is an error', () async {
      final s = await newSong('Fake');
      final bytes = await exportSongBundle([s.uuid]);
      db = deviceB;
      await db.into(db.songs).insert(bankSong(s.uuid));
      final plan = await planSongBundleImport(bytes);
      expect(plan.songs.single.outcome, ImportOutcome.error);
      expect(plan.songs.single.error, isNotNull);
      final r = await applySongBundleImport(plan, {});
      expect(r.songs.single.action, ImportAction.skipped);
      expect((await stored(s.uuid)).sourceBank, 'bank-1');
    });

    group('siblings', () {
      late Song a;
      late Song b;

      setUp(() async {
        db = deviceA;
        await db.into(db.songs).insert(bankSong('orig'));
        a = await copySongToLocal(bankSong('orig'));
        db = deviceB;
        await db.into(db.songs).insert(bankSong('orig'));
        b = await copySongToLocal(bankSong('orig'));
        db = deviceA;
      });

      test('identical content is a no-op, cue is pointed at mine', () async {
        final cue = cueOf(cueJson('c', [a.uuid]));
        final bytes = await exportSongBundle([a.uuid], cue: cue);
        db = deviceB;
        final plan = await planSongBundleImport(bytes);
        expect(plan.songs.single.outcome, ImportOutcome.identicalSibling);
        final r = await applySongBundleImport(plan, {});
        expect(r.songs.single.action, ImportAction.unchanged);
        expect(await songCount(), 2); // bank song + my copy
        expect(r.uuidRemap, {a.uuid: b.uuid});
        final slide = (r.cue!.cue!.content.single['song'] as Map);
        expect(slide['uuid'], b.uuid);
      });

      test('different content + replace keeps my uuid', () async {
        await edit(a.uuid, 'A edit');
        final bytes = await exportSongBundle([a.uuid]);
        db = deviceB;
        final plan = await planSongBundleImport(bytes);
        final p = plan.songs.single;
        expect(p.outcome, ImportOutcome.sibling);
        expect(p.existing!.uuid, b.uuid);
        expect(p.choices, [ImportChoice.replace, ImportChoice.keepBoth]);
        final r = await applySongBundleImport(plan, {
          a.uuid: ImportChoice.replace,
        });
        expect(r.songs.single.resultingUuid, b.uuid);
        expect(r.uuidRemap, {a.uuid: b.uuid});
        expect((await stored(b.uuid)).lyrics, 'A edit');
        expect(await songCount(), 2);
      });

      test('different content + keepBoth, cue slide remapped', () async {
        await edit(a.uuid, 'A edit');
        final cue = cueOf(cueJson('cue-kb', [a.uuid, 'bank-only']));
        final bytes = await exportSongBundle([a.uuid], cue: cue);
        db = deviceB;
        final r = await import(bytes, choices: {a.uuid: ImportChoice.keepBoth});
        final fresh = r.songs.single.resultingUuid!;
        expect(fresh, isNot(anyOf(a.uuid, b.uuid)));
        expect((await stored(b.uuid)).lyrics, 'bank lyrics');
        expect((await stored(fresh)).lyrics, 'A edit');
        final slides = r.cue!.cue!.content;
        expect((slides[0]['song'] as Map)['uuid'], fresh);
        expect((slides[1]['song'] as Map)['uuid'], 'bank-only');
        // origin link kept on the copy
        final links =
            await (db.songLinks.select()
                  ..where((l) => l.sourceUuid.equals(fresh)))
                .get();
        expect(links.map((l) => l.type), containsAll(SongLinkType.values));
      });

      test(
        'several matching copies: identical one wins, else the oldest',
        () async {
          db = deviceB;
          final b2 = await copySongToLocal(bankSong('orig'));
          await edit(b2.uuid, 'second');
          db = deviceA;
          final bytes = await exportSongBundle([a.uuid]); // == bank content
          db = deviceB;
          var plan = await planSongBundleImport(bytes);
          expect(plan.songs.single.outcome, ImportOutcome.identicalSibling);
          expect(plan.songs.single.existing!.uuid, b.uuid);

          await edit(b.uuid, 'first edited');
          plan = await planSongBundleImport(bytes);
          expect(plan.songs.single.outcome, ImportOutcome.sibling);
          expect(plan.songs.single.existing!.uuid, b.uuid);
        },
      );
    });

    test('a missing choice defaults to keepBoth', () async {
      final s = await newSong('Default');
      final fromB = await divergedBundle(s);
      db = deviceA;
      await edit(s.uuid, 'A version');
      final r = await import(fromB);
      expect(r.songs.single.action, ImportAction.createdCopy);
      expect((await stored(s.uuid)).lyrics, 'A version');
    });
  });

  group('cue', () {
    test('existing cue: keepBoth, overwrite, skip', () async {
      final s = await newSong('S');
      final cue = cueOf(cueJson('same-cue', [s.uuid]));
      final bytes = await exportSongBundle([], cue: cue);
      db = deviceB;
      await import(bytes);
      expect(
        await planSongBundleImport(bytes).then((p) => p.existingCue),
        isNotNull,
      );

      var r = await import(bytes, cueChoice: CueImportChoice.keepBoth);
      expect(r.cue!.action, CueImportAction.createdCopy);
      expect(r.cue!.cue!.uuid, isNot('same-cue'));
      expect(await db.cues.select().get(), hasLength(2));

      r = await import(bytes, cueChoice: CueImportChoice.overwrite);
      expect(r.cue!.action, CueImportAction.overwritten);
      r = await import(bytes, cueChoice: CueImportChoice.skip);
      expect(r.cue!.action, CueImportAction.skipped);
      expect(await db.cues.select().get(), hasLength(2));
    });
  });

  group('reading', () {
    test('tampered attachment is dropped and reported', () async {
      final s = await newSong('Tamper');
      await writeLocalSongAsset(s.uuid, 'pdf', Uint8List.fromList([5, 5, 5]));
      final good = await exportSongBundle([s.uuid]);
      final bad = tamper(good, (a) {
        final out = Archive();
        for (final f in a.files) {
          out.addFile(
            f.name.startsWith('assets/')
                ? ArchiveFile.bytes(f.name, [6, 6, 6])
                : ArchiveFile.bytes(f.name, f.readBytes()!),
          );
        }
        return out;
      });
      db = deviceB;
      final plan = await planSongBundleImport(bad);
      expect(plan.droppedAttachments.single.field, 'pdf');
      expect(plan.droppedAttachments.single.songUuid, s.uuid);
      expect(
        plan.songs.single.incoming.song.contentMap.containsKey('pdf'),
        isFalse,
      );
      await applySongBundleImport(plan, {});
      expect((await stored(s.uuid)).contentMap.containsKey('pdf'), isFalse);
      expect(await db.assets.select().get(), isEmpty);

      final missing = tamper(good, (a) {
        final out = Archive();
        for (final f in a.files.where((f) => !f.name.startsWith('assets/'))) {
          out.addFile(ArchiveFile.bytes(f.name, f.readBytes()!));
        }
        return out;
      });
      expect(
        (await planSongBundleImport(missing)).droppedAttachments,
        hasLength(1),
      );
    });

    test('unsupported version, unknown format, malformed', () async {
      await expectLater(
        planSongBundleImport(
          manifestBundle({
            'format': songBundleFormat,
            'version': songBundleVersion + 1,
            'songs': [],
            'cue': null,
          }),
        ),
        throwsA(
          isA<UnsupportedBundleVersion>().having(
            (e) => e.version,
            'version',
            songBundleVersion + 1,
          ),
        ),
      );
      await expectLater(
        planSongBundleImport(
          manifestBundle({'format': 'other', 'version': 1, 'songs': []}),
        ),
        throwsA(isA<UnknownBundleFormat>()),
      );
      await expectLater(
        planSongBundleImport(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<MalformedBundle>()),
      );
      await expectLater(
        planSongBundleImport(
          manifestBundle({
            'format': songBundleFormat,
            'version': 1,
            'songs': [
              {'uuid': 'x'},
            ],
          }),
        ),
        throwsA(isA<MalformedBundle>()),
      );
    });
  });

  test('apply is atomic', () async {
    final s1 = await newSong('Egy');
    final s2 = await newSong('Kettő');
    final bank = bankSong('orig');
    await db.into(db.songs).insert(bank);
    final copy = await copySongToLocal(bank); // has an origin link
    final bytes = await exportSongBundle([
      s1.uuid,
      s2.uuid,
      copy.uuid,
    ], cue: cueOf(cueJson('c', [s1.uuid])));

    db = deviceB;
    await db.customStatement(
      "CREATE TRIGGER fail_link BEFORE INSERT ON song_links "
      "BEGIN SELECT RAISE(ABORT, 'boom'); END;",
    );
    final plan = await planSongBundleImport(bytes);
    await expectLater(applySongBundleImport(plan, {}), throwsA(anything));

    expect(await db.songs.select().get(), isEmpty);
    expect(await db.assets.select().get(), isEmpty);
    expect(await db.cues.select().get(), isEmpty);
  });
}
