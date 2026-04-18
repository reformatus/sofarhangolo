import 'package:chord_transposer/chord_transposer.dart';
import 'package:dart_opensong/dart_opensong.dart' as os;
import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class LyricsView extends ConsumerWidget {
  LyricsView(
    this.song, {
    this.songSlide,
    this.forceSingleColumnLayout = false,
    super.key,
  });

  final Song song;
  final SongSlide? songSlide;
  // TODO this is a stopgap for in-cue scroll consistency. We have to redesign lyrics view so that it scrolls vertically, or cues to scroll vertically.
  final bool forceSingleColumnLayout;

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
          if (song.lyrics.isEmpty) {
            return Center(
              child: LErrorCard(
                type: LErrorType.warning,
                title: 'A dalhoz nem tartozik dalszöveg!',
                icon: Icons.error,
              ),
            );
          }

          final parser = LyricsParser.forFormat(song.lyricsFormat);
          final verses = parser.parse(song.lyrics);

          return SingleChildScrollView(
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
                  ...verses.map(
                    (verse) => SizedBox(
                      width: cardWidth,
                      child: VerseCard(
                        song,
                        verse as OpenSongVerse,
                        transpose: transpose,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class VerseCard extends ConsumerStatefulWidget {
  const VerseCard(this.song, this.verse, {required this.transpose, super.key});

  final OpenSongVerse verse;
  final Song song;
  final SongTranspose transpose;

  @override
  ConsumerState<VerseCard> createState() => _VerseCardState();
}

class _VerseCardState extends ConsumerState<VerseCard> {
  late final ScrollController cardController;

  @override
  void initState() {
    cardController = ScrollController();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final lyricsViewStyle = ref.watch(lyricsViewStylePreferencesProvider);

    return FadingEdgeScrollView.fromSingleChildScrollView(
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
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
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
                            os.UnsupportedLine(:final original) => LErrorCard(
                              type: LErrorType.info,
                              title: 'Ismeretlen sortípus',
                              message: original,
                              icon: Icons.question_mark,
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
  });

  final List<os.VerseLineSegment> segments;
  final os.VerseLineSegment segment;
  final Song song;
  final SongTranspose transpose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsViewStyle = ref.watch(lyricsViewStylePreferencesProvider);

    final chord = getTransposedChord(
      segment.chord,
      song.primaryKeyField?.pitch,
      transpose.finalTransposeBy,
    );

    final TextPainter chordPainter = TextPainter(
      text: TextSpan(
        text: chord ?? '',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: lyricsViewStyle.chordsSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final TextPainter lyricsPainter = TextPainter(
      text: TextSpan(
        text: segment.lyrics,
        style: TextStyle(fontSize: lyricsViewStyle.lyricsSize),
      ),
      textDirection: TextDirection.ltr,
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
              Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text(
                  chord ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: lyricsViewStyle.chordsSize,
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
                      style: TextStyle(fontSize: lyricsViewStyle.lyricsSize),
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
