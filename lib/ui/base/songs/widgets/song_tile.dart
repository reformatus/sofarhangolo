import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/bank/bank.dart';
import '../../../../data/database.dart';
import '../../../../data/song/extensions.dart';
import '../../../../data/song/song.dart';
import '../../../../services/connectivity/provider.dart';
import '../../../../services/app_links/navigation.dart';
import '../../../../services/songs/filter.dart';
import '../../../common/key_text.dart';

class LSongResultTile extends ConsumerWidget {
  const LSongResultTile(this.songResult, this.bank, {this.onTap, super.key});

  final SongResult songResult;
  final Bank? bank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Song song = songResult.song;
    final SongFulltextSearchResult? result = songResult.result;
    final List<String> downloadedAssets = songResult.downloadedAssets;
    final connection = ref.watch(connectionProvider);

    return ListTile(
      // far future todo dense on desktop (maybe even table?)
      onTap: () {
        onTap?.call();
        context.push(songRoutePath(song.uuid));
      },
      title: RichText(
        text: TextSpan(
          children: spansFromSnippet(
            result?.matchTitle ?? song.title,
            normalStyle: Theme.of(context).textTheme.bodyLarge!,
            highlightStyle: Theme.of(context).textTheme.bodyLarge!.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
      subtitle: result == null
          ? song.firstLine
                        .replaceAll(RegExp(r'[^a-zA-Z]'), '')
                        .startsWith(
                          song.title.replaceAll(RegExp(r'[^a-zA-Z]'), ''),
                        ) ||
                    song.firstLine.isEmpty
                ? null
                : Text(
                    song.firstLine,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                  )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasMatch(result.matchLyrics))
                  contentResultRow(
                    context,
                    Icons.text_snippet,
                    result.matchLyrics,
                  ),
              ],
            ),
      leading: bank?.tinyLogo != null
          ? Tooltip(
              message: bank!.name,
              child: Padding(
                padding: EdgeInsets.only(right: 5),
                child: SizedBox.square(
                  dimension: 26,
                  child: Image.memory(bank!.tinyLogo!),
                ),
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 100),
            child: Text(
              displayKeyFields(song.keyField),
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.clip,
            ),
          ),
          SizedBox(width: 10),
          if (downloadedAssets.isNotEmpty &&
              connection == ConnectionType.offline) ...[
            Tooltip(
              message: 'Kottakép letöltve',
              child: Icon(Icons.offline_pin, color: Colors.green[600]),
            ),
            SizedBox(width: 10),
          ],
          SongFeatures(song, downloadedAssets),
        ],
      ),
    );
  }

  Row contentResultRow(
    BuildContext context,
    IconData iconData,
    String? matchString,
  ) {
    return Row(
      children: [
        Icon(iconData, size: 18),
        SizedBox(width: 5),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: spansFromSnippet(
                matchString ?? "",
                normalStyle: Theme.of(context).textTheme.bodySmall!,
                highlightStyle: Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
          ),
        ),
      ],
    );
  }
}

class SongFeatures extends StatelessWidget {
  const SongFeatures(this.song, this.downloadedAssets, {super.key});

  final Song song;
  final List<String> downloadedAssets;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Tooltip(
        richMessage: TextSpan(
          children: [
            // TODO factor out to make configurable
            // TODO explain current applicable state instead of general info
            TextSpan(text: 'Tartalom: '),
            WidgetSpan(
              child: Icon(
                Icons.music_note_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            TextSpan(text: 'Kotta, '),
            WidgetSpan(
              child: Icon(
                Icons.audio_file_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            TextSpan(text: 'PDF, '),
            WidgetSpan(
              child: Icon(
                Icons.text_snippet_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            TextSpan(text: 'Dalszöveg, '),
            WidgetSpan(
              child: Icon(
                Icons.tag_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            TextSpan(text: 'Akkord'),
            TextSpan(text: '\nZöld: letöltve, Szürke: nem elérhető'),
          ],
        ),
        child: Wrap(
          direction: Axis.vertical,
          alignment: WrapAlignment.spaceEvenly,
          // TODO factor out to make configurable
          children: [
            indicatorIcon(
              context,
              Icons.music_note_outlined,
              available: song.hasSvg,
              downloaded: downloadedAssets.contains('svg'),
            ),
            indicatorIcon(
              context,
              Icons.audio_file_outlined,
              available: song.hasPdf,
              downloaded: downloadedAssets.contains('pdf'),
            ),
            indicatorIcon(
              context,
              Icons.text_snippet_outlined,
              available: song.hasLyrics,
              downloaded: song.hasLyrics,
            ),
            indicatorIcon(
              context,
              Icons.tag_outlined,
              available: song.hasChords,
              downloaded: song.hasChords,
            ),
          ],
        ),
      ),
    );
  }

  Widget indicatorIcon(
    BuildContext context,
    IconData iconData, {
    required bool available,
    bool downloaded = false,
  }) {
    Color? color;
    if (downloaded) {
      color = Colors.green[600];
    } else if (available) {
      color = null;
    } else {
      color = Colors.grey.withAlpha(80);
    }

    return Icon(iconData, color: color, size: 18);
  }
}

bool hasMatch(String? snippet) {
  if (snippet == null) return false;
  return snippet.contains(snippetTags.start) &&
      snippet.contains(snippetTags.end);
}

List<TextSpan> spansFromSnippet(
  String? snippet, {
  required TextStyle normalStyle,
  required TextStyle highlightStyle,
}) {
  List<TextSpan> spans = [];
  String remainingText = (snippet ?? "").replaceAll('\n', ' ');
  while (remainingText.contains(snippetTags.start) &&
      remainingText.contains(snippetTags.end)) {
    // Get the text before the match
    final int startIndex = remainingText.indexOf(snippetTags.start);
    if (startIndex > 0) {
      spans.add(
        TextSpan(
          text: remainingText.substring(0, startIndex),
          style: normalStyle,
        ),
      );
    }

    // Get the highlighted match
    remainingText = remainingText.substring(
      startIndex + snippetTags.start.length,
    );
    final int endIndex = remainingText.indexOf(snippetTags.end);
    spans.add(
      TextSpan(
        text: remainingText.substring(0, endIndex),
        style: highlightStyle,
      ),
    );

    // Update the remaining text after the match
    remainingText = remainingText.substring(endIndex + snippetTags.end.length);
  }

  // Add any remaining text that isn't highlighted
  if (remainingText.isNotEmpty) {
    spans.add(TextSpan(text: remainingText, style: normalStyle));
  }

  return spans;
}
