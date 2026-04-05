import 'package:flutter/material.dart';

import '../../../data/song/song.dart';
import '../../base/songs/widgets/filter/types/field_type.dart';

// Helper functions for song details
List<Widget> getDetailsSummaryContent(
  Song song,
  BuildContext context,
  SongFieldCatalog catalog,
) {
  const Set<String> fieldsToShowInDetailsSummary = {
    'composer',
    'lyricist',
    'translator',
  };

  List<Widget> detailsSummary = [];
  for (String field in fieldsToShowInDetailsSummary) {
    if (song.contentMap[field] != null && song.contentMap[field]!.isNotEmpty) {
      final definition = catalog[field] ?? fallbackSongFieldCatalog[field];
      if (definition == null) continue;
      detailsSummary.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              definition.icon,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 3),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                song.contentMap[field]!,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                softWrap: true,
              ),
            ),
          ],
        ),
      );
    }
  }
  return detailsSummary;
}

List<Widget> getDetailsContent(
  Song song,
  BuildContext context,
  SongFieldCatalog catalog,
) {
  const Set<String> fieldsToOmitFromDetails = {
    'title',
    'uuid',
    'sourceBank',
    'key',
    'lyrics',
    'opensong', // legacy
    'lyricsFormat',
    'first_line',
  };

  List<Widget> detailsContent = [];
  for (MapEntry<String, String> contentEntry in song.contentMap.entries) {
    if (fieldsToOmitFromDetails.contains(contentEntry.key)) continue;
    if (contentEntry.value.isNotEmpty) {
      final definition =
          catalog[contentEntry.key] ??
          fallbackSongFieldCatalog[contentEntry.key];
      if (definition != null) {
        detailsContent.add(
          ListTile(
            visualDensity: VisualDensity.compact,
            leading: Icon(definition.icon),
            title: Text(
              definition.titleHu,
              style: Theme.of(context).primaryTextTheme.labelMedium,
            ),
            subtitle: Text(contentEntry.value),
            subtitleTextStyle: Theme.of(context).listTileTheme.titleTextStyle,
          ),
        );
      }
    }
  }
  return detailsContent;
}
