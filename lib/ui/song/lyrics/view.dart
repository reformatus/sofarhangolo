import 'package:chord_transposer/chord_transposer.dart';
import 'package:dart_opensong/dart_opensong.dart' as os;
import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sofarhangolo/data/song/extensions.dart';

import '../../../data/cue/slide.dart';
import '../../../data/song/lyrics/parser.dart';
import '../../../data/song/song.dart';
import '../../../data/song/transpose.dart';
import '../../../services/key/get_transposed.dart';
import '../../../services/preferences/providers/lyrics_view_style.dart';
import '../../../services/song/verse_tag_pretty.dart';
import '../../common/error/card.dart';
import '../../cue/session/session_provider.dart';
import '../transpose/state.dart';
import '../widgets/report_song_button.dart';
import 'text_actions/lyrics_actions_menu.dart';
import 'text_actions/lyrics_selection_dialog.dart';
import 'text_actions/lyrics_text_actions.dart';

class LyricsView extends ConsumerWidget {
  LyricsView(
    this.song, {
    this.songSlide,
    this.forceSingleColumnLayout = false,
    this.textActionsEnabled = true,
    super.key,
  });

  final Song song;
  final SongSlide? songSlide;
  // TODO this is a stopgap for in-cue scroll consistency. We have to redesign lyrics view so that it scrolls vertically, or cues to scroll vertically.
  final bool forceSingleColumnLayout;

  /// Whether the lyrics text actions (long-press context menu, click-to-select
  /// dialog, hover highlight) are installed. Disabled in the presenter view,
  /// where stray taps must not open dialogs.
  final bool textActionsEnabled;

  final ChordTransposer transposer = ChordTransposer(
    notation: NoteNotation.germanWithAccidentals, // TODO configurable
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSongSlide = switch (songSlide) {
      null => null,
      final SongSlide cueSongSlide => switch (ref
          .watch(slideSnapshotProvider(cueSongSlide.uuid))
          .slide) {
        SongSlide currentSlide => currentSlide,
        _ => cueSongSlide,
      },
    };

    SongTranspose transpose = currentSongSlide != null
        ? currentSongSlide.transpose ?? SongTranspose()
        : ref.watch(transposeStateForProvider(song));
    final lyricsViewStyle = ref.watch(lyricsViewStylePreferencesProvider);

    return Material(
      child: LayoutBuilder(
        builder: (context, constraints) {
          //! Calculate layout
          int crossAxisCount = forceSingleColumnLayout
              ? 1
              : (constraints.maxWidth ~/ lyricsViewStyle.verseCardColumnWidth)
                    .clamp(1, 9999);
          double cardWidth = (constraints.maxWidth / crossAxisCount);

          // When scrolling sideways, make sure a bit of the next column is visible
          if (crossAxisCount > 1) cardWidth -= (30 / (crossAxisCount));

          //! Parse lyrics using format-specific parser
          if (!song.hasLyrics) {
            return Center(
              child: LErrorCard(
                type: LErrorType.warning,
                title: 'A dalhoz nem tartozik dalszöveg!',
                icon: Icons.error,
                // Content issue in the song's own bank, so the report goes to
                // that bank — and disappears for local songs.
                reportAction: ReportSongButton(song, filled: true),
              ),
            );
          }

          final parser = LyricsParser.forFormat(song.lyricsFormat);
          final verses = parser.parse(song.lyrics!);

          final scrollable = SingleChildScrollView(
            scrollDirection: crossAxisCount > 1
                ? Axis.horizontal
                : Axis.vertical,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Wrap(
                direction: Axis.vertical,
                children: [
                  if (transpose.capo != 0)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Capo: ${transpose.capo}',
                        style: TextStyle(fontSize: lyricsViewStyle.chordsSize),
                      ),
                    ),
                  ...verses.indexed.map(
                    (entry) => SizedBox(
                      width: cardWidth,
                      child: VerseCard(
                        song,
                        entry.$2 as OpenSongVerse,
                        transpose: transpose,
                        verseIndex: entry.$1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

          return LyricsTextActions(
            song: song,
            enabled: textActionsEnabled,
            child: scrollable,
          );
        },
      ),
    );
  }
}

class VerseCard extends ConsumerStatefulWidget {
  const VerseCard(
    this.song,
    this.verse, {
    required this.transpose,
    required this.verseIndex,
    super.key,
  });

  final OpenSongVerse verse;
  final Song song;
  final SongTranspose transpose;

  /// Index of [verse] in the parsed verse list, used for preselection.
  final int verseIndex;

  @override
  ConsumerState<VerseCard> createState() => _VerseCardState();
}

class _VerseCardState extends ConsumerState<VerseCard> {
  late final ScrollController cardController;
  bool _hovered = false;

  @override
  void initState() {
    cardController = ScrollController();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final lyricsViewStyle = ref.watch(lyricsViewStylePreferencesProvider);

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        // Only mouse clicks open the dialog; touch and stylus users get the
        // long-press context menu instead.
        onTapUp: (details) {
          if (details.kind == PointerDeviceKind.mouse) {
            showLyricsSelectionDialog(
              context,
              song: widget.song,
              initialVerseIndex: widget.verseIndex,
            );
          }
        },
        onSecondaryTapUp: (details) => showLyricsTextActionsMenu(
          context,
          song: widget.song,
          verse: widget.verse,
          verseIndex: widget.verseIndex,
          position: details.globalPosition,
        ),
        onLongPressStart: (details) => showLyricsTextActionsMenu(
          context,
          song: widget.song,
          verse: widget.verse,
          verseIndex: widget.verseIndex,
          position: details.globalPosition,
        ),
        child: FadingEdgeScrollView.fromSingleChildScrollView(
          child: SingleChildScrollView(
            controller: cardController,
            child: Padding(
              padding: EdgeInsets.only(top: 5, left: 5, right: 5),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.onPrimary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.verse.tag.isNotEmpty)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(5),
                            bottomRight: Radius.circular(5),
                          ),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        child: Text(
                          getPrettyVerseTagFrom(
                            widget.verse.type,
                            widget.verse.index,
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: lyricsViewStyle.verseTagSize,
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.only(
                        top: 5,
                        left: 10,
                        right: 10,
                        bottom: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: widget.verse.raw.parts
                            .map(
                              (versePart) => switch (versePart) {
                                os.VerseLine(:final segments) => Wrap(
                                  alignment: WrapAlignment.start,
                                  crossAxisAlignment: WrapCrossAlignment.start,
                                  children: segments
                                      .map(
                                        (segment) => LyricsSegment(
                                          song: widget.song,
                                          transpose: widget.transpose,
                                          segments: segments,
                                          segment: segment,
                                          highlightLyrics: _hovered,
                                        ),
                                      )
                                      .toList(),
                                ),
                                os.CommentLine(:final comment) => Text(
                                  comment,
                                  style: TextStyle(fontStyle: FontStyle.italic),
                                ),
                                os.NewSlide() => Divider(),
                                os.EmptyLine() => Text(''),
                                os.UnsupportedLine(:final original) =>
                                  LErrorCard(
                                    type: LErrorType.info,
                                    title: 'Ismeretlen sortípus',
                                    message: original,
                                    icon: Icons.question_mark,
                                    // Also a bank content issue: report it
                                    // there, or hide the action for locals.
                                    reportAction: ReportSongButton(
                                      widget.song,
                                      filled: true,
                                    ),
                                  ),
                              },
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LyricsSegment extends ConsumerWidget {
  const LyricsSegment({
    super.key,
    required this.song,
    required this.transpose,
    required this.segments,
    required this.segment,
    this.highlightLyrics = false,
  });

  final List<os.VerseLineSegment> segments;
  final os.VerseLineSegment segment;
  final Song song;
  final SongTranspose transpose;

  /// Draws a dotted underline under the lyric line (hover affordance).
  final bool highlightLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsViewStyle = ref.watch(lyricsViewStylePreferencesProvider);

    final chord = getTransposedChord(
      segment.chord,
      song.primaryKeyField?.pitch,
      transpose.finalTransposeBy,
    );

    final chordStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: lyricsViewStyle.chordsSize,
    );
    final lyricsStyle = TextStyle(fontSize: lyricsViewStyle.lyricsSize);

    // Text widgets merge in the ambient style, so measure through it (and the
    // text scale) to get the metrics that actually get laid out.
    final ambientStyle = DefaultTextStyle.of(context).style;
    final textScaler = MediaQuery.textScalerOf(context);

    final TextPainter chordPainter = TextPainter(
      // A glyph, so a segment without a chord still measures a full chord line.
      text: TextSpan(
        text: chord ?? 'C',
        style: ambientStyle.merge(chordStyle),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();

    final TextPainter lyricsPainter = TextPainter(
      text: TextSpan(
        text: segment.lyrics,
        style: ambientStyle.merge(lyricsStyle),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();

    final double chordWidth = chord != null ? chordPainter.width + 4 : 0;

    double hyphenWidth = 0;

    if (segment.hyphenAfter) {
      hyphenWidth = (chordWidth - lyricsPainter.width).clamp(
        0,
        double.infinity,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (segments.any((s) => s.chord != null))
              // The chord slot keeps a full chord line's height whatever the
              // segment holds, so the lyrics of every segment in a line share
              // one baseline. The chord itself is measured with a tight line
              // box and sits at the bottom of the slot, hugging its lyrics;
              // the slot's height (and so the line height) is unchanged.
              SizedBox(
                height: chordPainter.height,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  // Hug the chord: filling the width would push every segment
                  // onto its own run.
                  widthFactor: 1,
                  child: Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Text(
                      chord ?? '',
                      style: chordStyle.copyWith(height: 1),
                    ),
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (segment.lyrics.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: Text(
                      segment.lyrics,
                      style: lyricsStyle.copyWith(
                        decoration: highlightLyrics
                            ? TextDecoration.underline
                            : null,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  )
                else
                  SizedBox(height: 8),
                if (hyphenWidth > 2)
                  SizedBox(
                    width: hyphenWidth,
                    child: ClipRect(
                      child: Center(
                        child: Text(
                          "-",
                          style: TextStyle(
                            fontSize: lyricsViewStyle.lyricsSize,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
