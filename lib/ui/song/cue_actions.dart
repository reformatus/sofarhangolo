import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/log/logger.dart';
import '../../data/song/song.dart';
import '../../data/song/transpose.dart';
import '../cue/session/cue_session.dart';
import '../cue/session/session_provider.dart';
import 'state.dart';
import '../../services/ui/messenger_service.dart';
import '../../data/cue/slide.dart';

class SongCueActionState {
  const SongCueActionState({
    required this.activeCueSession,
    required this.songInActiveCue,
  });

  factory SongCueActionState.fromSession(CueSession? session, Song song) {
    return SongCueActionState(
      activeCueSession: session,
      songInActiveCue:
          session?.slides.whereType<SongSlide>().any(
            (slide) => slide.song.uuid == song.uuid,
          ) ??
          false,
    );
  }

  final CueSession? activeCueSession;
  final bool songInActiveCue;

  bool get hasActiveCue => activeCueSession != null;

  String get mobileAddToCueLabel => hasActiveCue && !songInActiveCue
      ? 'Másik listához adás'
      : 'Hozzáadás listához';

  String get desktopSearchHint => hasActiveCue && !songInActiveCue
      ? 'Másik listához adás...'
      : 'Hozzáadás listához...';

  bool get canAddToOpenCue => hasActiveCue && !songInActiveCue;
  bool get showOpenCueAddedState => hasActiveCue && songInActiveCue;
}

Future<void> addSongToActiveCue({
  required WidgetRef ref,
  required Song song,
  required SongTranspose? transpose,
  required CueSession session,
}) async {
  try {
    final currentViewType = await ref.read(
      viewTypeForProvider(song, null).future,
    );

    ref
        .read(activeCueSessionProvider.notifier)
        .addSlide(
          SongSlide.from(song, viewType: currentViewType, transpose: transpose),
        );

    messengerService.showSnackBarReplacingCurrent(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          '${song.title} hozzáadva a listához: ${session.cue.title}',
        ),
        duration: const Duration(seconds: 4),
      ),
      forceHideAfter: const Duration(seconds: 4),
    );
  } catch (e, s) {
    log.severe(
      'Nem sikerült alapértelmezett nézetet betölteni gyors hozzáadáshoz: ${song.uuid}',
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
  }
}
