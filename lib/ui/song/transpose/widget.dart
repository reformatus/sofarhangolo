import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/song/transpose.dart';
import '../state.dart';
import '../../../data/cue/slide.dart';

import '../../../data/song/song.dart';
import '../../cue/session/session_provider.dart';
import '../../../services/key/get_transposed.dart';
import '../../common/key_text.dart';
import 'state.dart';

class TransposeResetButton extends ConsumerWidget {
  const TransposeResetButton(
    this.song, {
    this.songSlide,
    required this.isCompact,
    super.key,
  });

  final bool isCompact;
  final Song song;
  final SongSlide? songSlide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (songSlide != null) {
      final currentSongSlide = switch (ref
          .watch(slideSnapshotProvider(songSlide!.uuid))
          .slide) {
        SongSlide currentSlide => currentSlide,
        _ => songSlide!,
      };
      final transpose = currentSongSlide.transpose ?? SongTranspose();

      if (transpose.semitones != 0 || transpose.capo != 0) {
        return IconButton(
          tooltip: 'Transzponálás visszaállítása',
          onPressed: () => ref
              .read(activeCueSessionProvider.notifier)
              .updateSlide(
                currentSongSlide.copyWith(
                  transpose: SongTranspose(semitones: 0, capo: 0),
                ),
              ),
          icon: Icon(Icons.replay),
          iconSize: isCompact ? 18 : null,
          visualDensity: VisualDensity.compact,
        );
      }

      return SizedBox.shrink();
    }

    final transpose = ref.watch(transposeStateForProvider(song));
    if (transpose.semitones != 0 || transpose.capo != 0) {
      return IconButton(
        tooltip: 'Transzponálás visszaállítása',
        onPressed: () =>
            ref.read(transposeStateForProvider(song).notifier).state =
                SongTranspose(),
        icon: Icon(Icons.replay),
        iconSize: isCompact ? 18 : null,
        visualDensity: VisualDensity.compact,
      );
    } else {
      return SizedBox.shrink();
    }
  }
}

class TransposeControls extends ConsumerWidget {
  const TransposeControls(this.song, {this.songSlide, super.key});

  final Song song;
  final SongSlide? songSlide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (songSlide != null) {
      final currentSongSlide = switch (ref
          .watch(slideSnapshotProvider(songSlide!.uuid))
          .slide) {
        SongSlide currentSlide => currentSlide,
        _ => songSlide!,
      };
      final transpose = currentSongSlide.transpose ?? SongTranspose();

      void updateTranspose(SongTranspose newTranspose) {
        ref
            .read(activeCueSessionProvider.notifier)
            .updateSlide(currentSongSlide.copyWith(transpose: newTranspose));
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          sectionTitle(context, 'TRANSZPONÁLÁS'),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () {
                  int newSemitones = transpose.semitones - 1;
                  if (newSemitones < -11) newSemitones = 0;
                  updateTranspose(
                    SongTranspose(
                      semitones: newSemitones,
                      capo: transpose.capo,
                    ),
                  );
                },
                icon: Icon(Icons.expand_more),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      transpose.semitones.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: Theme.of(
                          context,
                        ).textTheme.bodyLarge!.fontSize,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: () {
                  int newSemitones = transpose.semitones + 1;
                  if (newSemitones > 11) newSemitones = 0;
                  updateTranspose(
                    SongTranspose(
                      semitones: newSemitones,
                      capo: transpose.capo,
                    ),
                  );
                },
                icon: Icon(Icons.expand_less),
              ),
            ],
          ),
          sectionTitle(context, 'CAPO'),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () {
                  int newCapo = transpose.capo - 1;
                  if (newCapo < 0) newCapo = 11;
                  updateTranspose(
                    SongTranspose(
                      semitones: transpose.semitones,
                      capo: newCapo,
                    ),
                  );
                },
                icon: Icon(Icons.remove),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      transpose.capo.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: Theme.of(
                          context,
                        ).textTheme.bodyLarge!.fontSize,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: () {
                  int newCapo = transpose.capo + 1;
                  if (newCapo > 11) newCapo = 0;
                  updateTranspose(
                    SongTranspose(
                      semitones: transpose.semitones,
                      capo: newCapo,
                    ),
                  );
                },
                icon: Icon(Icons.add),
              ),
            ],
          ),
        ],
      );
    }

    final transpose = ref.watch(transposeStateForProvider(song));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        sectionTitle(context, 'TRANSZPONÁLÁS'),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: () {
                final controller = ref.read(
                  transposeStateForProvider(song).notifier,
                );
                var newSemitones = controller.state.semitones - 1;
                if (newSemitones < -11) newSemitones = 0;
                controller.state = SongTranspose(
                  semitones: newSemitones,
                  capo: controller.state.capo,
                );
              },
              icon: Icon(Icons.expand_more),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    transpose.semitones.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: Theme.of(context).textTheme.bodyLarge!.fontSize,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              onPressed: () {
                final controller = ref.read(
                  transposeStateForProvider(song).notifier,
                );
                var newSemitones = controller.state.semitones + 1;
                if (newSemitones > 11) newSemitones = 0;
                controller.state = SongTranspose(
                  semitones: newSemitones,
                  capo: controller.state.capo,
                );
              },
              icon: Icon(Icons.expand_less),
            ),
          ],
        ),
        sectionTitle(context, 'CAPO'),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: () {
                final controller = ref.read(
                  transposeStateForProvider(song).notifier,
                );
                var newCapo = controller.state.capo - 1;
                if (newCapo < 0) newCapo = 11;
                controller.state = SongTranspose(
                  semitones: controller.state.semitones,
                  capo: newCapo,
                );
              },
              icon: Icon(Icons.remove),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    transpose.capo.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: Theme.of(context).textTheme.bodyLarge!.fontSize,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              onPressed: () {
                final controller = ref.read(
                  transposeStateForProvider(song).notifier,
                );
                var newCapo = controller.state.capo + 1;
                if (newCapo > 11) newCapo = 0;
                controller.state = SongTranspose(
                  semitones: controller.state.semitones,
                  capo: newCapo,
                );
              },
              icon: Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  Widget sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: EdgeInsets.only(top: 7, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
        ),
      ),
    );
  }
}

class TransposeCard extends ConsumerWidget {
  const TransposeCard({super.key, required this.song, this.songSlide});

  final Song song;
  final SongSlide? songSlide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (songSlide != null) {
      final currentSongSlide = switch (ref
          .watch(slideSnapshotProvider(songSlide!.uuid))
          .slide) {
        SongSlide currentSlide => currentSlide,
        _ => songSlide!,
      };
      final transpose = currentSongSlide.transpose ?? SongTranspose();

      if (currentSongSlide.viewType != SongViewType.chords) {
        return SizedBox.shrink();
      }

      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 250),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Column(
              children: [
                SizedBox(
                  height: 30,
                  child: Row(
                    children: [
                      Text(
                        song.primaryKeyField != null
                            ? displayKeyField(
                                getTransposedKey(
                                  song.primaryKeyField!,
                                  transpose.semitones,
                                ),
                              )
                            : 'Hangnem',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      TransposeResetButton(
                        song,
                        songSlide: currentSongSlide,
                        isCompact: false,
                      ),
                    ],
                  ),
                ),
                TransposeControls(song, songSlide: currentSongSlide),
              ],
            ),
          ),
        ),
      );
    }

    final transpose = ref.watch(transposeStateForProvider(song));
    final viewTypeAsync = ref.watch(viewTypeForProvider(song, songSlide));

    if (viewTypeAsync.value != SongViewType.chords) {
      return SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 250),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            children: [
              SizedBox(
                height: 30,
                child: Row(
                  children: [
                    Text(
                      song.primaryKeyField != null
                          ? displayKeyField(
                              getTransposedKey(
                                song.primaryKeyField!,
                                transpose.semitones,
                              ),
                            )
                          : 'Hangnem',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    TransposeResetButton(
                      song,
                      songSlide: songSlide,
                      isCompact: false,
                    ),
                  ],
                ),
              ),
              TransposeControls(song, songSlide: songSlide),
            ],
          ),
        ),
      ),
    );
  }
}
