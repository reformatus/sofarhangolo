// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;

import 'package:sofarhangolo/data/database.dart';

/// Migration tests are tagged so they can be excluded until migrations are implemented.
/// Run with: flutter test --exclude-tags=migration
@Tags(['migration'])
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = LyricDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // The following template shows how to write tests ensuring your migrations
  // preserve existing data.
  // Testing this can be useful for migrations that change existing columns
  // (e.g. by alterating their type or constraints). Migrations that only add
  // tables or columns typically don't need these advanced tests. For more
  // information, see https://drift.simonbinder.eu/migrations/tests/#verifying-data-integrity
  // TODO: This generated template shows how these tests could be written. Adopt
  // it to your own needs when testing migrations with data integrity.
  test('migration from v1 to v2 does not corrupt data', () async {
    // Add data to insert into the old database, and the expected rows after the
    // migration.
    final oldBanksData = <v1.BanksData>[];
    final expectedNewBanksData = <v2.BanksData>[];

    final oldSongsData = <v1.SongsData>[
      const v1.SongsData(
        id: 1,
        uuid: 'song-1',
        sourceBank: null,
        contentMap: '{}',
        title: 'Migration Song',
        opensong: '[V1]\n Első sor',
        composer: null,
        lyricist: null,
        translator: null,
        keyField: '',
        userNote: null,
      ),
    ];
    final expectedNewSongsData = <v2.SongsData>[
      const v2.SongsData(
        id: 1,
        uuid: 'song-1',
        sourceBank: null,
        contentMap: '{}',
        title: 'Migration Song',
        lyrics: '[V1]\n Első sor',
        lyricsFormat: 'opensong',
        keyField: '',
      ),
    ];

    final oldAssetsData = <v1.AssetsData>[];
    final expectedNewAssetsData = <v2.AssetsData>[];

    final oldCuesData = <v1.CuesData>[];
    final expectedNewCuesData = <v2.CuesData>[];

    final oldPreferenceStorageData = <v1.PreferenceStorageData>[];
    final expectedNewPreferenceStorageData = <v2.PreferenceStorageData>[];

    final oldSongsFtsData = <v1.SongsFtsData>[];
    final expectedNewSongsFtsData = <v2.SongsFtsData>[
      const v2.SongsFtsData(title: 'Migration Song', lyrics: '[V1]\n Első sor'),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: LyricDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.banks, oldBanksData);
        batch.insertAll(oldDb.songs, oldSongsData);
        batch.insertAll(oldDb.assets, oldAssetsData);
        batch.insertAll(oldDb.cues, oldCuesData);
        batch.insertAll(oldDb.preferenceStorage, oldPreferenceStorageData);
        batch.insertAll(oldDb.songsFts, oldSongsFtsData);
      },
      validateItems: (newDb) async {
        expect(expectedNewBanksData, await newDb.select(newDb.banks).get());
        expect(expectedNewSongsData, await newDb.select(newDb.songs).get());
        expect(expectedNewAssetsData, await newDb.select(newDb.assets).get());
        expect(expectedNewCuesData, await newDb.select(newDb.cues).get());
        expect(
          expectedNewPreferenceStorageData,
          await newDb.select(newDb.preferenceStorage).get(),
        );
        expect(
          expectedNewSongsFtsData,
          await newDb.select(newDb.songsFts).get(),
        );
      },
    );
  });

  test('migration from v3 to v4 sets bank lastUpdated sentinel', () async {
    final oldBanksData = <v3.BanksData>[
      const v3.BanksData(
        id: 1,
        uuid: 'bank-1',
        logo: null,
        tinyLogo: null,
        name: 'Migration Bank',
        description: null,
        legal: null,
        aboutLink: null,
        contactEmail: null,
        baseUrl: 'https://example.com',
        parallelUpdateJobs: 1,
        amountOfSongsInRequest: 10,
        noCms: 0,
        songFields: '{}',
        isEnabled: 1,
        isOfflineMode: 0,
        lastUpdated: '2025-03-01T12:00:00',
        failedSongUuids: null,
        totalSongsInBank: 1,
      ),
    ];
    final expectedNewBanksData = <v4.BanksData>[
      const v4.BanksData(
        id: 1,
        uuid: 'bank-1',
        logo: null,
        tinyLogo: null,
        name: 'Migration Bank',
        description: null,
        legal: null,
        aboutLink: null,
        contactEmail: null,
        baseUrl: 'https://example.com',
        parallelUpdateJobs: 1,
        amountOfSongsInRequest: 10,
        noCms: 0,
        songFields: '{}',
        isEnabled: 1,
        isOfflineMode: 0,
        lastUpdated: '1900-01-01T00:00:00',
        failedSongUuids: null,
        totalSongsInBank: 1,
      ),
    ];

    final oldSongsData = <v3.SongsData>[
      const v3.SongsData(
        id: 1,
        uuid: 'song-1',
        sourceBank: 'bank-1',
        contentMap: '{}',
        title: 'Migration Song',
        lyrics: '[V3]\n Első sor',
        lyricsFormat: 'opensong',
        keyField: 'C-dur',
      ),
    ];
    final expectedNewSongsData = <v4.SongsData>[
      const v4.SongsData(
        id: 1,
        uuid: 'song-1',
        sourceBank: 'bank-1',
        contentMap: '{}',
        title: 'Migration Song',
        lyrics: '[V3]\n Első sor',
        lyricsFormat: 'opensong',
        keyField: 'C-dur',
      ),
    ];

    final oldAssetsData = <v3.AssetsData>[];
    final expectedNewAssetsData = <v4.AssetsData>[];

    final oldCuesData = <v3.CuesData>[];
    final expectedNewCuesData = <v4.CuesData>[];

    final oldPreferenceStorageData = <v3.PreferenceStorageData>[];
    final expectedNewPreferenceStorageData = <v4.PreferenceStorageData>[];

    final oldSongsFtsData = <v3.SongsFtsData>[
      const v3.SongsFtsData(title: 'Migration Song', lyrics: '[V3]\n Első sor'),
    ];
    final expectedNewSongsFtsData = <v4.SongsFtsData>[
      const v4.SongsFtsData(title: 'Migration Song', lyrics: '[V3]\n Első sor'),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 4,
      createOld: v3.DatabaseAtV3.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: LyricDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.banks, oldBanksData);
        batch.insertAll(oldDb.songs, oldSongsData);
        batch.insertAll(oldDb.assets, oldAssetsData);
        batch.insertAll(oldDb.cues, oldCuesData);
        batch.insertAll(oldDb.preferenceStorage, oldPreferenceStorageData);
        batch.insertAll(oldDb.songsFts, oldSongsFtsData);
      },
      validateItems: (newDb) async {
        expect(expectedNewBanksData, await newDb.select(newDb.banks).get());
        expect(expectedNewSongsData, await newDb.select(newDb.songs).get());
        expect(expectedNewAssetsData, await newDb.select(newDb.assets).get());
        expect(expectedNewCuesData, await newDb.select(newDb.cues).get());
        expect(
          expectedNewPreferenceStorageData,
          await newDb.select(newDb.preferenceStorage).get(),
        );
        expect(
          expectedNewSongsFtsData,
          await newDb.select(newDb.songsFts).get(),
        );
      },
    );
  });

  test('migration from v4 to v5 moves key data into content_map', () async {
    final oldBanksData = <v4.BanksData>[
      const v4.BanksData(
        id: 1,
        uuid: 'bank-1',
        logo: null,
        tinyLogo: null,
        name: 'Migration Bank',
        description: null,
        legal: null,
        aboutLink: null,
        contactEmail: null,
        baseUrl: 'https://example.com',
        parallelUpdateJobs: 1,
        amountOfSongsInRequest: 10,
        noCms: 0,
        songFields: '{}',
        isEnabled: 1,
        isOfflineMode: 0,
        lastUpdated: '1900-01-01T00:00:00',
        failedSongUuids: null,
        totalSongsInBank: 1,
      ),
    ];
    final expectedNewBanksData = <v5.BanksData>[
      const v5.BanksData(
        id: 1,
        uuid: 'bank-1',
        logo: null,
        tinyLogo: null,
        name: 'Migration Bank',
        description: null,
        legal: null,
        aboutLink: null,
        contactEmail: null,
        baseUrl: 'https://example.com',
        parallelUpdateJobs: 1,
        amountOfSongsInRequest: 10,
        noCms: 0,
        songFields: '{}',
        isEnabled: 1,
        isOfflineMode: 0,
        lastUpdated: '1900-01-01T00:00:00',
        failedSongUuids: null,
        totalSongsInBank: 1,
      ),
    ];

    final oldSongsData = <v4.SongsData>[
      const v4.SongsData(
        id: 1,
        uuid: 'song-1',
        sourceBank: 'bank-1',
        contentMap: '{}',
        title: 'Migration Song',
        lyrics: '[V4]\n Első sor',
        lyricsFormat: 'opensong',
        keyField: 'C-dur',
      ),
    ];
    final expectedNewSongsData = <v5.SongsData>[
      const v5.SongsData(
        id: 1,
        uuid: 'song-1',
        sourceBank: 'bank-1',
        contentMap: '{"key":"C-dur"}',
        title: 'Migration Song',
        lyrics: '[V4]\n Első sor',
        lyricsFormat: 'opensong',
      ),
    ];

    final oldAssetsData = <v4.AssetsData>[];
    final expectedNewAssetsData = <v5.AssetsData>[];

    final oldCuesData = <v4.CuesData>[];
    final expectedNewCuesData = <v5.CuesData>[];

    final oldPreferenceStorageData = <v4.PreferenceStorageData>[];
    final expectedNewPreferenceStorageData = <v5.PreferenceStorageData>[];

    final oldSongsFtsData = <v4.SongsFtsData>[
      const v4.SongsFtsData(title: 'Migration Song', lyrics: '[V4]\n Első sor'),
    ];
    final expectedNewSongsFtsData = <v5.SongsFtsData>[
      const v5.SongsFtsData(title: 'Migration Song', lyrics: '[V4]\n Első sor'),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 4,
      newVersion: 5,
      createOld: v4.DatabaseAtV4.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: LyricDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.banks, oldBanksData);
        batch.insertAll(oldDb.songs, oldSongsData);
        batch.insertAll(oldDb.assets, oldAssetsData);
        batch.insertAll(oldDb.cues, oldCuesData);
        batch.insertAll(oldDb.preferenceStorage, oldPreferenceStorageData);
        batch.insertAll(oldDb.songsFts, oldSongsFtsData);
      },
      validateItems: (newDb) async {
        expect(expectedNewBanksData, await newDb.select(newDb.banks).get());
        expect(expectedNewSongsData, await newDb.select(newDb.songs).get());
        expect(expectedNewAssetsData, await newDb.select(newDb.assets).get());
        expect(expectedNewCuesData, await newDb.select(newDb.cues).get());
        expect(
          expectedNewPreferenceStorageData,
          await newDb.select(newDb.preferenceStorage).get(),
        );
        expect(
          expectedNewSongsFtsData,
          await newDb.select(newDb.songsFts).get(),
        );
      },
    );
  });
}
