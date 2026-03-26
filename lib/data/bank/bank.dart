import 'dart:convert';

import 'package:drift/drift.dart';

//import 'package:path_provider/path_provider.dart';

import '../database.dart';

/*
  far future todo: support bank discovery based on url
  baseUrl/discover => {
    name? description?
    supports lastUpdated? (is static?)
    available filter types?
  }
 */

/*
  far future todo: online bank discovery service
  api.lyricapp.org/banks => [...list of urls to autodiscover banks from]
  including name, description, metadata type, etc
  user can pick and choose
  banks can announce themselves (get added to community banks) (federation!)
  moderators can promote banks to officially endorsed
 */

// these get added to the database on first run
// todo add a way to add and disable banks

class Bank extends Insertable<Bank> {
  final int id;
  final String uuid;
  final Uint8List? logo;
  final Uint8List? tinyLogo;
  final String name;
  final String? description;
  final String? legal;
  final String? aboutLink;
  final String? contactEmail;
  final Uri baseUrl;
  final int parallelUpdateJobs;
  final int amountOfSongsInRequest;
  final bool noCms;
  final Map<String, dynamic> songFields;
  bool isEnabled;
  bool isOfflineMode;
  DateTime? lastUpdated;
  final String? failedSongUuids;
  final int? totalSongsInBank;

  Bank(
    this.id,
    this.uuid,
    this.logo,
    this.tinyLogo,
    this.name,
    this.description,
    this.legal,
    this.aboutLink,
    this.contactEmail,
    this.baseUrl,
    this.parallelUpdateJobs,
    this.amountOfSongsInRequest,
    this.noCms,
    this.songFields,
    this.isEnabled,
    this.isOfflineMode,
    this.lastUpdated,
    this.failedSongUuids,
    this.totalSongsInBank,
  );

  List<ProtoSong> get failedProtoSongs {
    final rawFailedSongs = failedSongUuids;
    if (rawFailedSongs == null || rawFailedSongs.trim().isEmpty) return [];

    try {
      final decoded = jsonDecode(rawFailedSongs);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((entry) {
            final uuid = entry['uuid'];
            final title = entry['title'];
            if (uuid is! String || title is! String) return null;
            return ProtoSong(uuid, title);
          })
          .whereType<ProtoSong>()
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  static String? encodeFailedProtoSongs(Map<String, String> songsByUuid) {
    if (songsByUuid.isEmpty) return null;

    return jsonEncode(
      songsByUuid.entries
          .map((entry) => {'uuid': entry.key, 'title': entry.value})
          .toList(growable: false),
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return BanksCompanion(
      id: Value.absent(),
      uuid: Value(uuid),
      logo: Value.absentIfNull(logo),
      tinyLogo: Value.absentIfNull(tinyLogo),
      name: Value(name),
      description: Value(description),
      legal: Value(legal),
      baseUrl: Value(baseUrl),
      parallelUpdateJobs: Value(parallelUpdateJobs),
      amountOfSongsInRequest: Value(amountOfSongsInRequest),
      noCms: Value(noCms),
      songFields: Value(songFields),
      isEnabled: Value(isEnabled),
      isOfflineMode: Value(isOfflineMode),
      lastUpdated: Value(lastUpdated),
      failedSongUuids: Value(failedSongUuids),
      totalSongsInBank: Value(totalSongsInBank),
    ).toColumns(nullToAbsent);
  }
}

@UseRowClass(Bank)
class Banks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  BlobColumn get logo => blob().nullable()();
  BlobColumn get tinyLogo => blob().nullable()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get legal => text().nullable()();
  TextColumn get aboutLink => text().nullable()();
  TextColumn get contactEmail => text().nullable()();
  TextColumn get baseUrl => text().map(const UriConverter())();
  IntColumn get parallelUpdateJobs => integer()();
  IntColumn get amountOfSongsInRequest => integer()();
  BoolColumn get noCms => boolean()();
  TextColumn get songFields => text().map(const MapConverter())();
  BoolColumn get isEnabled => boolean()();
  BoolColumn get isOfflineMode => boolean()();
  DateTimeColumn get lastUpdated => dateTime().nullable()();
  TextColumn get failedSongUuids => text().nullable()();
  IntColumn get totalSongsInBank => integer().nullable()();
}

class ProtoSong {
  final String uuid;
  final String title;

  ProtoSong(this.uuid, this.title);

  factory ProtoSong.fromJson(Map<String, dynamic> json) =>
      ProtoSong(json['uuid'] as String, json['title'] as String);

  @override
  String toString() => '$title [$uuid]';
}
