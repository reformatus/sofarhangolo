import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/v4.dart';

import '../bank/bank.dart';
import '../database.dart';
import 'lyrics/format.dart';
import 'lyrics/parser.dart';

class Song extends Insertable<Song> {
  final String uuid;
  final String? sourceBank;
  final String title;
  final String? lyrics;
  final LyricsFormat lyricsFormat;
  final String? variationOf;
  final List<KeyField> keyField;

  Map<String, String> contentMap;

  /// Records which fields the song owns in its own (raw) bank data, as
  /// opposed to fields inherited from a variation parent. Set once when the
  /// song is parsed from the bank API and carried unchanged through
  /// variation merging - merging never alters rawness, only a fresh bank
  /// update rewrites it.
  ///
  /// Null only for rows written before this column existed. Such rows are
  /// treated as frozen by the variation merge: they are never re-merged
  /// locally, and recover their metadata on the next full bank refetch.
  final SongFieldOwnership? ownership;

  static String? _nonBlankString(dynamic value) {
    if (value is! String) return null;
    return value.trim().isEmpty ? null : value;
  }

  factory Song.fromBankApiJson(Map<String, dynamic> json, {Bank? sourceBank}) {
    try {
      // Check for new 'lyrics' field first, but fall back to legacy 'opensong'
      // when lyrics is missing or blank.
      final String? lyricsFromLyricsField = _nonBlankString(json['lyrics']);
      final String? lyricsFromOpenSongField = _nonBlankString(json['opensong']);
      final String? lyricsContent =
          lyricsFromLyricsField ?? lyricsFromOpenSongField;

      // Infer format from lyrics when available, otherwise default to opensong.
      final LyricsFormat format = lyricsFromLyricsField != null
          ? LyricsFormat.fromString(json['lyrics_format'])
          : LyricsFormat.opensong;

      if (!mandatoryFields.every((field) => json.containsKey(field))) {
        throw Exception(
          'Missing mandatory fields in: ${json['title']} (${json['uuid']})',
        );
      }
      final variationOf = _nonBlankString(json['variation_of']);

      // Build contentMap excluding fields that have dedicated columns,
      // tracking which entries the song owns (non-blank raw values).
      final contentMap = <String, String>{};
      final ownedContentKeys = <String>{};
      for (final e in json.entries) {
        if (_excludedFromContentMap.contains(e.key)) continue;
        final rawValue = e.value.toString();
        contentMap[e.key] = rawValue;
        if (e.value != null &&
            rawValue.trim().isNotEmpty &&
            rawValue != 'null') {
          ownedContentKeys.add(e.key);
        }
      }

      final keyField = KeyField.fromStringList(json['key']);

      return Song(
        uuid: json['uuid'],
        title: json['title'],
        lyrics: lyricsContent,
        lyricsFormat: format,
        variationOf: variationOf,
        keyField: keyField,
        contentMap: contentMap,
        sourceBank: sourceBank?.uuid,
        ownership: SongFieldOwnership(
          contentKeys: ownedContentKeys,
          keyField: keyField.isNotEmpty,
          lyrics: lyricsContent?.trim().isNotEmpty ?? false,
        ),
      );
    } catch (e) {
      throw Exception(
        'Invalid song data in: ${json['title']} (${json['uuid']})\nError: $e',
      );
    }
  }

  Song({
    required this.uuid,
    required this.title,
    this.lyrics,
    this.lyricsFormat = LyricsFormat.opensong,
    this.variationOf,
    required this.keyField,
    required this.contentMap,
    this.sourceBank,
    this.ownership,
  });

  /// Creates a new local song with a fresh uuid. Local songs live in the
  /// app's local bank and are never touched by bank updates.
  factory Song.local({
    required String title,
    String? lyrics,
    LyricsFormat lyricsFormat = LyricsFormat.opensong,
    List<KeyField> keyField = const [],
    Map<String, String> contentMap = const {},
    String? sourceBank,
  }) {
    return Song(
      uuid: UuidV4().generate(),
      title: title,
      lyrics: lyrics,
      lyricsFormat: lyricsFormat,
      keyField: keyField,
      contentMap: contentMap,
      sourceBank: sourceBank,
    );
  }

  Song copyWith({
    String? uuid,
    String? sourceBank,
    String? title,
    String? lyrics,
    LyricsFormat? lyricsFormat,
    String? variationOf,
    List<KeyField>? keyField,
    Map<String, String>? contentMap,
    SongFieldOwnership? ownership,
  }) {
    return Song(
      uuid: uuid ?? this.uuid,
      sourceBank: sourceBank ?? this.sourceBank,
      title: title ?? this.title,
      lyrics: lyrics ?? this.lyrics,
      lyricsFormat: lyricsFormat ?? this.lyricsFormat,
      variationOf: variationOf ?? this.variationOf,
      keyField: keyField ?? this.keyField,
      contentMap: contentMap ?? this.contentMap,
      ownership: ownership ?? this.ownership,
    );
  }

  String? get firstLine {
    return lyrics != null
        ? LyricsParser.forFormat(lyricsFormat).getFirstLine(lyrics!)
        : null;
  }

  KeyField? get primaryKeyField {
    if (keyField.isEmpty) return null;
    return keyField.first;
  }

  /// Deterministic hash over the song's content (title, lyrics, key and
  /// remaining content fields), stable across processes and devices.
  ///
  /// Persisted into cue shares and local-copy links to detect content drift,
  /// so it must not use [Object.hash] (which is salted per process) and must
  /// ignore identity fields (uuid, sourceBank).
  String get contentHash {
    final sortedContentMap = Map.fromEntries(
      contentMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final payload = jsonEncode({
      'title': title,
      'lyrics': lyrics,
      'keyField': keyField.map((e) => e.toString()).toList(),
      'contentMap': sortedContentMap,
    });
    return md5.convert(utf8.encode(payload)).toString();
  }

  /// Whether [other] carries the same values for the fields the variation
  /// merge can change: contentMap, keyField and lyrics. Identity fields are
  /// always taken from the song itself and therefore never differ.
  bool sameMergeableContentAs(Song other) {
    return _contentMapEquals(contentMap, other.contentMap) &&
        _listEquals(keyField, other.keyField) &&
        lyrics == other.lyrics;
  }

  static bool _contentMapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (other is! Song) return false;
    return uuid == other.uuid;
  }

  @override
  int get hashCode => uuid.hashCode;

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return SongsCompanion(
      uuid: Value(uuid),
      sourceBank: Value(sourceBank),
      contentMap: Value(contentMap),
      title: Value(title),
      lyrics: Value(lyrics),
      lyricsFormat: Value(lyricsFormat),
      variationOf: Value(variationOf),
      keyField: Value(keyField),
      ownership: Value(ownership),
    ).toColumns(nullToAbsent);
  }
}

/// Fields that are stored in dedicated columns and should not be duplicated in contentMap.
const Set<String> _excludedFromContentMap = {
  'uuid',
  'title',
  'lyrics',
  'opensong', // legacy field name
  'lyricsFormat',
  'lyrics_format',
  'variation_of',
  'key',
};

/// Mandatory fields that must be present in API JSON (lyrics checked separately).
const List<String> mandatoryFields = ['uuid', 'title'];

@TableIndex(name: 'songs_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'songs_variation_of', columns: {#variationOf})
@UseRowClass(Song)
class Songs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get sourceBank => text().nullable().references(Banks, #uuid)();
  TextColumn get contentMap => text().map(const SongContentConverter())();
  TextColumn get title => text()();
  TextColumn get lyrics => text().nullable()();
  TextColumn get lyricsFormat => text()
      .withDefault(const Constant('opensong'))
      .map(const LyricsFormatConverter())();
  TextColumn get variationOf => text().nullable()();
  TextColumn get keyField => text().map(const KeyFieldConverter())();
  TextColumn get ownership =>
      text().nullable().map(const SongFieldOwnershipConverter())();
}

/// Which fields of a song come from its own bank data rather than being
/// inherited from a variation parent.
class SongFieldOwnership {
  /// Content keys present with non-blank values in the song's own data.
  final Set<String> contentKeys;
  final bool keyField;
  final bool lyrics;

  const SongFieldOwnership({
    required this.contentKeys,
    required this.keyField,
    required this.lyrics,
  });

  factory SongFieldOwnership.fromJson(Map<String, dynamic> json) {
    return SongFieldOwnership(
      contentKeys: ((json['contentKeys'] as List?) ?? const [])
          .cast<String>()
          .toSet(),
      keyField: json['keyField'] == true,
      lyrics: json['lyrics'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contentKeys': contentKeys.toList()..sort(),
      'keyField': keyField,
      'lyrics': lyrics,
    };
  }

  @override
  bool operator ==(Object other) {
    if (other is! SongFieldOwnership) return false;
    return keyField == other.keyField &&
        lyrics == other.lyrics &&
        contentKeys.length == other.contentKeys.length &&
        contentKeys.containsAll(other.contentKeys);
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(contentKeys), keyField, lyrics);
}

class SongFieldOwnershipConverter
    extends TypeConverter<SongFieldOwnership, String> {
  const SongFieldOwnershipConverter();

  @override
  SongFieldOwnership fromSql(String fromDb) {
    return SongFieldOwnership.fromJson(
      jsonDecode(fromDb) as Map<String, dynamic>,
    );
  }

  @override
  String toSql(SongFieldOwnership value) {
    return jsonEncode(value.toJson());
  }
}

class SongContentConverter extends TypeConverter<Map<String, String>, String> {
  const SongContentConverter();

  @override
  Map<String, String> fromSql(String fromDb) {
    return (jsonDecode(fromDb) as Map).cast<String, String>();
  }

  @override
  String toSql(Map<String, String> value) {
    return jsonEncode(value);
  }
}

class KeyFieldConverter extends TypeConverter<List<KeyField>, String> {
  const KeyFieldConverter();

  @override
  List<KeyField> fromSql(String fromDb) {
    return KeyField.fromStringList(fromDb);
  }

  @override
  String toSql(List<KeyField> value) {
    return value.map((e) => e.toString()).join(', ');
  }
}

class KeyField {
  final String pitch;
  final String mode;

  KeyField(this.pitch, this.mode);

  static KeyField? fromString(String? value) {
    if (value == null || value.isEmpty) return null;

    // TODO handle multiple keys with a key list
    /*if (value.split(', ').length > 1) {
      throw UnsupportedError('Unsupported key field with multiple keys!');
    }*/
    value = value.split(', ').first;

    var parts = value.split('-');
    if (parts.length != 2) {
      throw Exception('Invalid key field: $value');
    }
    return KeyField(parts[0], parts[1]);
  }

  static List<KeyField> fromStringList(String? value) {
    if (value == null || value.isEmpty) return [];
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) => KeyField.fromString(item)!)
        .toList();
  }

  @override
  String toString() {
    return '$pitch-$mode';
  }

  @override
  bool operator ==(Object other) {
    if (other is! KeyField) return false;
    if (pitch == other.pitch && mode == other.mode) return true;
    return false;
  }

  @override
  int get hashCode => Object.hash(pitch, mode);
}
