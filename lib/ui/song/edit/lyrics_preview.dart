import 'dart:math';

import 'package:flutter/material.dart';

import '../../../data/song/lyrics/parser.dart';
import '../../../data/song/song.dart';
import '../../../data/song/transpose.dart';
import '../lyrics/view.dart';

/// Live lyrics preview: parses the editor's text as it changes and lays the
/// verses out like the song page does.
class LyricsPreview extends StatelessWidget {
  const LyricsPreview({super.key, required this.song, required this.text});

  final Song song;
  final TextEditingController text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colors.surfaceContainer,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: text,
        builder: (context, value, _) => LayoutBuilder(
          builder: (context, constraints) {
            final verses = LyricsParser.forFormat(
              song.lyricsFormat,
            ).parse(value.text);
            final verseWidth = min(constraints.maxWidth, 560.0);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: colors.outline,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Előnézet',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: colors.outline),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: Wrap(
                        direction: Axis.vertical,
                        children: [
                          ...verses.indexed.map(
                            (entry) => SizedBox(
                              width: verseWidth,
                              child: VerseCard(
                                song,
                                entry.$2 as OpenSongVerse,
                                transpose: SongTranspose(),
                                verseIndex: entry.$1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
