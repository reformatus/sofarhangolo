import 'dart:convert';

import 'package:drift/drift.dart';

import '../bank/bank.dart';
import '../database.dart';
import 'lyrics/format.dart';
import 'lyrics/parser.dart';

class Song extends Insertable<Song> {
  final String uuid;
  final String? sourceBank;
  final String title;
  final String lyrics;
  final LyricsFormat lyricsFormat;

  Map<String, String> contentMap;

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
      if (lyricsContent == null) {
        throw Exception(
          'Missing lyrics content (neither "lyrics" nor "opensong" field found)',
        );
      }

      // Infer format from lyrics when available, otherwise default to opensong.
      final LyricsFormat format = lyricsFromLyricsField != null
          ? LyricsFormat.fromString(json['lyrics_format'])
          : LyricsFormat.opensong;

      if (!mandatoryFields.every((field) => json.containsKey(field))) {
        throw Exception(
          'Missing mandatory fields in: ${json['title']} (${json['uuid']})',
        );
      }

      // Build contentMap excluding fields that have dedicated columns
      final contentMap = Map<String, String>.fromEntries(
        json.entries
            .where((e) => !_excludedFromContentMap.contains(e.key))
            .map((e) => MapEntry(e.key, e.value.toString())),
      );

      return Song(
        uuid: json['uuid'],
        title: json['title'],
        lyrics: lyricsContent,
        lyricsFormat: format,
        contentMap: contentMap,
        sourceBank: sourceBank?.uuid,
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
    required this.lyrics,
    this.lyricsFormat = LyricsFormat.opensong,
    required this.contentMap,
    this.sourceBank,
  });

  List<KeyField> get keyField => KeyField.fromStringList(contentMap['key']);

  String get firstLine {
    return LyricsParser.forFormat(lyricsFormat).getFirstLine(lyrics);
  }

  KeyField? get primaryKeyField {
    if (keyField.isEmpty) return null;
    return keyField.first;
  }

  int get contentHash => Object.hash(jsonEncode(contentMap), sourceBank);

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
};

/// Mandatory fields that must be present in API JSON (lyrics checked separately).
const List<String> mandatoryFields = ['uuid', 'title'];

@TableIndex(name: 'songs_uuid', columns: {#uuid}, unique: true)
@UseRowClass(Song)
class Songs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get sourceBank => text().nullable().references(Banks, #uuid)();
  TextColumn get contentMap => text().map(const SongContentConverter())();
  TextColumn get title => text()();
  TextColumn get lyrics => text()();
  TextColumn get lyricsFormat => text()
      .withDefault(const Constant('opensong'))
      .map(const LyricsFormatConverter())();
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
