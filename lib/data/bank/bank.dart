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

/// How a bank's content is reached.
enum BankAccess {
  /// Content is downloaded from a remote API ([Bank.baseUrl]).
  remote,

  /// Content lives in the local database and is user-editable.
  local,
}

/// The provenance of a remote bank's content.
enum BankSource {
  /// Endorsed banks listed by the official bank discovery API.
  official,

  /// Self-hosted or otherwise unofficial remote banks.
  unofficial,
}

/// Well-known uuid of the app's single local bank. The row itself is created
/// by the database bootstrap and migrations - never write it from services.
const String localBankUuid = 'c0ffee00-0000-4000-8000-000000000001';

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
  final BankAccess access;

  /// Provenance of remote content; null for the local bank.
  final BankSource? source;
  final Uri? _baseUrl;
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
    this.access,
    this.source,
    Uri? baseUrl,
    this.parallelUpdateJobs,
    this.amountOfSongsInRequest,
    this.noCms,
    this.songFields,
    this.isEnabled,
    this.isOfflineMode,
    this.lastUpdated,
    this.failedSongUuids,
    this.totalSongsInBank,
  ) : _baseUrl = baseUrl;

  /// Base url for remote API calls. Only remote banks have one; accessing
  /// it on a local bank is a programming error.
  Uri get baseUrl {
    final url = _baseUrl;
    if (url == null) {
      throw StateError('Bank $uuid has no base url');
    }
    return url;
  }

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
      access: Value(access),
      source: Value.absentIfNull(source),
      baseUrl: Value.absentIfNull(_baseUrl),
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
  IntColumn get access => intEnum<BankAccess>()
      // 0 == BankAccess.remote; spelled out so the generated migration
      // steps don't need to import the enum.
      .withDefault(Constant(0))();
  IntColumn get source => intEnum<BankSource>().nullable()();
  TextColumn get baseUrl => text().map(const UriConverter()).nullable()();
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
