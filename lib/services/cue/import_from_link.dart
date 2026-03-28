import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cue/cue.dart';
import '../../main.dart';
import '../../ui/common/confirm_dialog.dart';
import '../cue/from_uuid.dart';
import '../song/from_uuid.dart';
import '../cue/write_cue.dart';
import 'compression.dart';

/// Result of importing a cue from a deep link
class CueImportResult {
  final Cue cue;
  final String? slideUuid;

  CueImportResult(this.cue, this.slideUuid);

  /// Returns the navigation path for this imported cue
  String getNavigationPath() {
    return Uri(
      pathSegments: ['cue', cue.uuid, 'edit'],
      queryParameters: Map.fromEntries([
        if (slideUuid != null) MapEntry('slide', slideUuid!),
      ]),
    ).toString();
  }
}

/// Imports a cue from compressed data in a deep link (cueData endpoint)
///
/// Handles:
/// - Decompression of MessagePack + gzip + base64url data
/// - Duplicate detection and user confirmation for overwrites
/// - Optional slide parameter for navigation
Future<CueImportResult> importCueFromCompressedData(
  String encodedData,
  Map<String, String> queryParameters,
) async {
  final json = decompressCueFromUrl(encodedData);
  await _expandShortSongUuids(json);
  final cue = await _importCueJson(
    json,
    initialSlideUuid: queryParameters['slide'],
  );
  final slideUuid = queryParameters['slide'];

  return CueImportResult(cue, slideUuid);
}

Future<void> _expandShortSongUuids(Map<String, dynamic> cueJson) async {
  final content = cueJson['content'];
  if (content is! List) return;

  for (final slideEntry in content) {
    if (slideEntry is! Map) continue;
    if (slideEntry['slideType'] != 'song') continue;

    final song = slideEntry['song'];
    if (song is! Map) continue;

    final shortUuid = song['uuid'];
    if (shortUuid is! String || shortUuid.isEmpty) continue;

    song['uuid'] = await resolveSongUuidFromPrefix(shortUuid);
  }
}

/// Imports a cue from plain JSON in a deep link (cueJson endpoint - backward compatible)
///
/// Handles:
/// - JSON decoding
/// - Duplicate detection and user confirmation for overwrites
/// - Optional slide parameter for navigation
Future<CueImportResult> importCueFromJson(
  String jsonString,
  Map<String, String> queryParameters,
) async {
  final json = jsonDecode(jsonString);
  final cue = await _importCueJson(
    json,
    initialSlideUuid: queryParameters['slide'],
  );
  final slideUuid = queryParameters['slide'];

  return CueImportResult(cue, slideUuid);
}

/// Common logic for importing a cue from JSON data
///
/// Checks if cue already exists and shows confirmation dialog if so.
/// Otherwise inserts as new cue.
Future<Cue> _importCueJson(Map json, {String? initialSlideUuid}) async {
  Cue? existingCue = await dbWatchCueWithUuid(json['uuid']).first;

  if (existingCue == null) {
    // New cue - insert it
    return await insertCueFromJson(json: json);
  } else {
    // Existing cue - ask user if they want to overwrite
    final BuildContext? context = appNavigatorKey.currentContext;
    if (context == null) {
      return existingCue;
    }
    if (!context.mounted) {
      return existingCue;
    }

    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    Cue cue = existingCue;

    await showConfirmDialog(
      context,
      title: 'A linkben megnyitott lista már létezik. Felülírod?',
      actionLabel: 'Felülírás',
      actionIcon: Icons.edit_note,
      actionOnPressed: () async {
        cue = await updateCueFromJson(
          json: json,
          container: container,
          initialSlideUuid: initialSlideUuid,
        );
      },
    );

    return cue;
  }
}
