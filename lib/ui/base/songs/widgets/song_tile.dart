import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/bank/bank.dart';
import '../../../../data/cue/slide.dart';
import '../../../../data/database.dart';
import '../../../../data/log/logger.dart';
import '../../../../data/song/extensions.dart';
import '../../../../data/song/song.dart';
import '../../../../services/app_links/navigation.dart';
import '../../../../services/connectivity/provider.dart';
import '../../../../services/songs/filter.dart';
import '../../../../services/ui/messenger_service.dart';
import '../../../cue/session/session_provider.dart';
import '../../../song/state.dart';
import '../../../common/key_text.dart';

const double _hideDownloadIndicatorsBelowWidth = 560;

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
    final showActiveCueQuickAdd = ref.watch(
      activeCueSessionProvider.select(
        (sessionAsync) => sessionAsync.value != null,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final hideSongFeatures =
            showActiveCueQuickAdd &&
            constraints.maxWidth < _hideDownloadIndicatorsBelowWidth;
        final leadingChildren = <Widget>[
          if (showActiveCueQuickAdd)
            Padding(
              padding: EdgeInsets.only(right: 10),
              child: ActiveCueQuickAddButton(song: song),
            ),
          if (bank?.tinyLogo != null)
            Tooltip(
              message: bank!.name,
              child: Padding(
                padding: const EdgeInsets.only(right: 5),
                child: SizedBox.square(
                  dimension: 26,
                  child: Image.memory(bank!.tinyLogo!),
                ),
              ),
            ),
        ];
        final trailingChildren = <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              displayKeyFields(song.keyField),
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.clip,
            ),
          ),
          if (!hideSongFeatures) ...[
            if (downloadedAssets.isNotEmpty &&
                connection == ConnectionType.offline)
              Tooltip(
                message: 'Kottakép letöltve',
                child: Icon(Icons.offline_pin, color: Colors.green[600]),
              ),
            SongFeatures(song, downloadedAssets),
          ],
        ];

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
          minLeadingWidth: leadingChildren.isEmpty ? 40 : 0,
          leading: leadingChildren.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: leadingChildren.separatedBy(
                    const SizedBox(width: 4),
                  ),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: trailingChildren.separatedBy(const SizedBox(width: 10)),
          ),
        );
      },
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

extension _SeparatedWidgets on List<Widget> {
  List<Widget> separatedBy(Widget separator) {
    if (isEmpty) {
      return const [];
    }

    return [
      for (int i = 0; i < length; i++) ...[if (i > 0) separator, this[i]],
    ];
  }
}

class ActiveCueQuickAddButton extends ConsumerStatefulWidget {
  const ActiveCueQuickAddButton({required this.song, super.key});

  final Song song;

  @override
  ConsumerState<ActiveCueQuickAddButton> createState() =>
      _ActiveCueQuickAddButtonState();
}

class _ActiveCueQuickAddButtonState
    extends ConsumerState<ActiveCueQuickAddButton> {
  bool _isAdding = false;

  Future<void> _handleAdd() async {
    final session = ref.read(activeCueSessionProvider).value;
    if (session == null || _isAdding) {
      return;
    }

    setState(() => _isAdding = true);
    try {
      final defaultViewType = await ref.read(
        viewTypeForProvider(widget.song, null).future,
      );

      ref
          .read(activeCueSessionProvider.notifier)
          .addSlide(SongSlide.from(widget.song, viewType: defaultViewType));

      messengerService.showSnackBarReplacingCurrent(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            '${widget.song.title} hozzáadva a listához: ${session.cue.title}',
          ),
          duration: const Duration(seconds: 4),
        ),
        forceHideAfter: const Duration(seconds: 4),
      );
    } catch (e, s) {
      log.severe(
        'Nem sikerült alapértelmezett nézetet betölteni gyors hozzáadáshoz: ${widget.song.uuid}',
        e,
        s,
      );
      messengerService.showSnackBarReplacingCurrent(
        const SnackBar(
          showCloseIcon: true,
          content: Text('Nem sikerült hozzáadni dalt a listához.'),
          duration: Duration(seconds: 4),
        ),
        forceHideAfter: const Duration(seconds: 4),
      );
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(
      activeCueSessionProvider.select((sessionAsync) => sessionAsync.value),
    );

    if (session == null) {
      return const SizedBox.shrink();
    }

    final songAlreadyInCue = session.slides.whereType<SongSlide>().any(
      (slide) => slide.song.uuid == widget.song.uuid,
    );

    if (songAlreadyInCue) {
      return IconButton(
        tooltip: 'Újra hozzáadás ehhez a listához',
        onPressed: _isAdding ? null : _handleAdd,
        icon: _isAdding
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      );
    }

    return IconButton.filledTonal(
      tooltip: '${session.cue.title} listához adás',
      onPressed: _isAdding ? null : _handleAdd,
      icon: _isAdding
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add),
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
