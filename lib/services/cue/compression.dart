import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:msgpack_dart/msgpack_dart.dart';

Map<String, dynamic> _withShortSongUuids(Map<String, dynamic> cueJson) {
  final result = Map<String, dynamic>.from(cueJson);
  final content = result['content'];

  if (content is List) {
    result['content'] = content.map((slideEntry) {
      if (slideEntry is! Map) return slideEntry;

      final slide = Map<String, dynamic>.from(slideEntry);
      if (slide['slideType'] != 'song') return slide;

      final song = slide['song'];
      if (song is! Map) return slide;

      final songMap = Map<String, dynamic>.from(song);
      final uuid = songMap['uuid'];
      if (uuid is String && uuid.isNotEmpty) {
        final dashIndex = uuid.indexOf('-');
        songMap['uuid'] = dashIndex == -1 ? uuid : uuid.substring(0, dashIndex);
      }

      slide['song'] = songMap;
      return slide;
    }).toList();
  }

  return result;
}

/// Removes null values from a JSON map recursively to reduce size
Map<String, dynamic> _removeNulls(Map<String, dynamic> json) {
  final result = <String, dynamic>{};

  for (final entry in json.entries) {
    if (entry.value == null) {
      continue; // Skip null values
    }

    if (entry.value is Map<String, dynamic>) {
      result[entry.key] = _removeNulls(entry.value as Map<String, dynamic>);
    } else if (entry.value is List) {
      result[entry.key] = (entry.value as List).map((item) {
        if (item is Map<String, dynamic>) {
          return _removeNulls(item);
        }
        return item;
      }).toList();
    } else {
      result[entry.key] = entry.value;
    }
  }

  return result;
}

/// Ensures all expected keys exist in the JSON map, initializing missing ones to null
Map<String, dynamic> _ensureKeys(Map json, List<String> expectedKeys) {
  final result = Map<String, dynamic>.from(json);

  for (final key in expectedKeys) {
    result.putIfAbsent(key, () => null);
  }

  return result;
}

/// Compresses a cue JSON object for URL sharing
///
/// Process:
/// 1. Remove null values to reduce data size
/// 2. Serialize with MessagePack (binary format)
/// 3. Compress with gzip
/// 4. Encode as base64url for URL safety
String compressCueForUrl(Map<String, dynamic> cueJson) {
  // Step 1: Replace full song UUIDs with their first segment.
  final shortened = _withShortSongUuids(cueJson);

  // Step 2: Remove nulls
  final cleaned = _removeNulls(shortened);

  // Step 3: MessagePack serialization
  final packed = serialize(cleaned);

  // Step 4: Gzip compression
  final compressed = GZipEncoder().encode(packed);

  // Step 5: Base64URL encoding
  return base64Url.encode(compressed);
}

/// Decompresses a cue data string from URL
///
/// Process:
/// 1. Decode from base64url
/// 2. Decompress with gzip
/// 3. Deserialize with MessagePack
/// 4. Restore missing keys as null
Map<String, dynamic> decompressCueFromUrl(String encoded) {
  // Expected keys in a Cue object (for null restoration)
  const expectedCueKeys = [
    'uuid',
    'title',
    'description',
    'cueVersion',
    'content',
  ];

  // Step 1: Base64URL decode
  final compressed = base64Url.decode(encoded);

  // Step 2: Gzip decompress
  final packed = GZipDecoder().decodeBytes(compressed);

  // Step 3: MessagePack deserialize
  final dynamic deserialized = deserialize(Uint8List.fromList(packed));

  // Step 4: Ensure all expected keys exist
  if (deserialized is! Map) {
    throw Exception('Deserialized data is not a Map');
  }

  return _ensureKeys(deserialized, expectedCueKeys);
}
