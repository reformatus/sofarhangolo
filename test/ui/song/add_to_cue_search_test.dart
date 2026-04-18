import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/transpose.dart';
import 'package:sofarhangolo/services/cue/cues.dart';
import 'package:sofarhangolo/services/preferences/preferences_parent.dart';
import 'package:sofarhangolo/services/preferences/providers/song_view_order.dart';
import 'package:sofarhangolo/services/ui/messenger_service.dart';
import 'package:sofarhangolo/ui/base/cue_shell_inset.dart';
import 'package:sofarhangolo/ui/cue/session/cue_session.dart';
import 'package:sofarhangolo/ui/cue/session/session_provider.dart';
import 'package:sofarhangolo/ui/song/state.dart';
import 'package:sofarhangolo/ui/song/song_cue_actions.dart';
import 'package:sofarhangolo/ui/song/widgets/content.dart';
import 'package:sofarhangolo/ui/song/widgets/mobile_bottom_bar.dart';

import '../../harness/fake_messenger.dart';
import '../../harness/test_database.dart';

class _FakeActiveCueSession extends ActiveCueSession {
  _FakeActiveCueSession(this.initialSession);

  final CueSession? initialSession;

  @override
  Future<CueSession?> build() async => initialSession;
}

Song _createSong(String uuid, String title) {
  return Song.fromBankApiJson({
    'uuid': uuid,
    'title': title,
    'lyrics': '<song><lyrics>$title</lyrics></song>',
    'lyricsFormat': 'opensong',
  });
}

CueSession _createSession({
  required Cue cue,
  required List<Slide> slides,
  String? currentSlideUuid,
}) {
  cue.replaceSlides(slides);
  return CueSession(cue: cue, currentSlideUuid: currentSlideUuid);
}

Future<Cue> _insertCue({
  required String uuid,
  required String title,
  String description = '',
}) {
  return db
      .into(db.cues)
      .insertReturning(
        CuesCompanion(
          id: const Value.absent(),
          uuid: Value(uuid),
          title: Value(title),
          description: Value(description),
          cueVersion: Value(currentCueVersion),
          content: const Value([]),
        ),
      );
}

Future<void> _insertSong(Song song) async {
  await db.into(db.songs).insert(song, mode: InsertMode.insertOrReplace);
}

Future<ProviderContainer> _pumpSubject(
  WidgetTester tester, {
  required Song song,
  CueSession? session,
  List<Cue>? cues,
  bool isDesktop = false,
  bool showOpenCueAction = false,
}) async {
  late ProviderContainer container;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        songViewOrderPreferencesProvider.overrideWithValue(
          SongViewOrderPreferencesClass(songViewOrder: [SongViewType.lyrics]),
        ),
        if (session != null)
          activeCueSessionProvider.overrideWith(
            () => _FakeActiveCueSession(session),
          ),
        if (cues != null)
          watchAllCuesProvider.overrideWith((ref) => Stream.value(cues)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              if (isDesktop) {
                return Center(
                  child: SizedBox(
                    width: 900,
                    height: 700,
                    child: SongCueActions(
                      song: song,
                      isDesktop: true,
                      viewType: SongViewType.lyrics,
                      transpose: SongTranspose(),
                    ),
                  ),
                );
              }

              return Center(
                child: SongCueActions(
                  song: song,
                  isDesktop: false,
                  showOpenCueAction: showOpenCueAction,
                  viewType: SongViewType.lyrics,
                  transpose: SongTranspose(),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
  return container;
}

Future<void> _pumpTabletBottomBar(
  WidgetTester tester, {
  required Song song,
  CueSession? session,
  List<Cue>? cues,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        songViewOrderPreferencesProvider.overrideWithValue(
          SongViewOrderPreferencesClass(songViewOrder: [SongViewType.lyrics]),
        ),
        if (session != null)
          activeCueSessionProvider.overrideWith(
            () => _FakeActiveCueSession(session),
          ),
        if (cues != null)
          watchAllCuesProvider.overrideWith((ref) => Stream.value(cues)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 820,
              child: MobileBottomBar(
                song: song,
                constraints: const BoxConstraints.tightFor(
                  width: 820,
                  height: 50,
                ),
                actionButtonsScrollController: ScrollController(),
                transposeOverlayVisible: ValueNotifier(false),
                showOpenCueAction: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

Future<void> _pumpSongPageContent(
  WidgetTester tester, {
  required Song song,
  CueSession? session,
  List<Cue>? cues,
  required CueShellPresentation shellPresentation,
  required Size size,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        songViewOrderPreferencesProvider.overrideWithValue(
          SongViewOrderPreferencesClass(songViewOrder: [SongViewType.lyrics]),
        ),
        if (session != null)
          activeCueSessionProvider.overrideWith(
            () => _FakeActiveCueSession(session),
          ),
        if (cues != null)
          watchAllCuesProvider.overrideWith((ref) => Stream.value(cues)),
      ],
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          home: CueShellInset(
            bottomInset: shellPresentation == CueShellPresentation.bottomOverlay
                ? 56
                : 0,
            presentation: shellPresentation,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: SongPageContent(
                song: song,
                detailsSheetScrollController: ScrollController(),
                actionButtonsScrollController: ScrollController(),
                transposeOverlayVisible: ValueNotifier(false),
                onShowDetailsSheet: (_, _, _) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  late LyricDatabase testDb;
  late MessengerService originalMessenger;
  late FakeMessengerService fakeMessenger;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    originalMessenger = messengerService;
    fakeMessenger = FakeMessengerService();
    messengerService = fakeMessenger;
  });

  tearDown(() async {
    messengerService = originalMessenger;
    await testDb.close();
  });

  testWidgets('shows filled action when no active cue exists', (tester) async {
    final song = _createSong('song-1', 'Song');

    await _pumpSubject(tester, song: song, cues: const []);

    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byIcon(Icons.playlist_add), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Hozzáadás listához'),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('tablet keeps mobile add action when no active cue exists', (
    tester,
  ) async {
    final song = _createSong('song-1', 'Song');

    await _pumpSubject(
      tester,
      song: song,
      cues: const [],
      showOpenCueAction: true,
    );

    expect(
      find.widgetWithText(FilledButton, 'Hozzáadás listához'),
      findsOneWidget,
    );
    expect(find.text('Hozzáadás megnyitott listához'), findsNothing);
  });

  testWidgets('shows secondary action when active cue exists for other songs', (
    tester,
  ) async {
    final song = _createSong('song-1', 'Song');
    final otherSong = _createSong('song-2', 'Other');
    final cue = Cue(1, 'cue-1', 'Cue', '', currentCueVersion, const []);
    final session = _createSession(
      cue: cue,
      slides: [SongSlide.from(otherSong, viewType: SongViewType.lyrics)],
    );

    await _pumpSubject(tester, song: song, session: session, cues: const []);

    expect(
      find.widgetWithText(TextButton, 'Másik listához adás'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Másik listához adás'),
      findsNothing,
    );
  });

  testWidgets('shows text add action when song is already in active cue', (
    tester,
  ) async {
    final song = _createSong('song-1', 'Song');
    final cue = Cue(1, 'cue-1', 'Cue', '', currentCueVersion, const []);
    final session = _createSession(
      cue: cue,
      slides: [SongSlide.from(song, viewType: SongViewType.lyrics)],
    );

    await _pumpSubject(tester, song: song, session: session, cues: const []);

    expect(
      find.widgetWithText(TextButton, 'Hozzáadás listához'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('adding to cue without active session activates selected cue', (
    tester,
  ) async {
    final song = _createSong('song-1', 'Song');
    await _insertSong(song);
    final cue = await _insertCue(uuid: 'cue-1', title: 'Target cue');

    final container = await _pumpSubject(tester, song: song);

    await tester.tap(find.text('Hozzáadás listához'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Target cue'));
    await tester.pumpAndSettle();

    final session = container.read(activeCueSessionProvider).value;
    final storedCue = await (db.select(
      db.cues,
    )..where((c) => c.uuid.equals(cue.uuid))).getSingle();

    expect(session, isA<CueSession>());
    expect(session!.cue.uuid, cue.uuid);
    expect(session.slides.whereType<SongSlide>().single.song.uuid, song.uuid);
    expect(storedCue.content, isNotEmpty);
    expect(storedCue.content.single['slideType'], 'song');
    expect(fakeMessenger.shownSnackBars, isNotEmpty);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('desktop search hint uses add copy when no active cue exists', (
    tester,
  ) async {
    final song = _createSong('song-1', 'Song');

    await _pumpSubject(tester, song: song, isDesktop: true, cues: const []);

    expect(find.text('Hozzáadás listához...'), findsOneWidget);
    expect(find.text('Hozzáadás megnyitott listához'), findsNothing);
    expect(find.text('Megnyitott listához adva'), findsNothing);
  });

  testWidgets(
    'desktop actions show open cue add button and other-cue hint for songs outside active cue',
    (tester) async {
      final song = _createSong('song-1', 'Song');
      final otherSong = _createSong('song-2', 'Other');
      final cue = Cue(1, 'cue-1', 'Cue', '', currentCueVersion, const []);
      final session = _createSession(
        cue: cue,
        slides: [SongSlide.from(otherSong, viewType: SongViewType.lyrics)],
      );

      await _pumpSubject(
        tester,
        song: song,
        session: session,
        isDesktop: true,
        cues: const [],
      );

      expect(
        find.widgetWithText(FilledButton, 'Hozzáadás megnyitott listához'),
        findsOneWidget,
      );
      expect(find.text('Másik listához adás...'), findsOneWidget);
    },
  );

  testWidgets(
    'tablet actions show open cue add button and mobile other-cue action',
    (tester) async {
      final song = _createSong('song-1', 'Song');
      final otherSong = _createSong('song-2', 'Other');
      final cue = Cue(1, 'cue-1', 'Cue', '', currentCueVersion, const []);
      final session = _createSession(
        cue: cue,
        slides: [SongSlide.from(otherSong, viewType: SongViewType.lyrics)],
      );

      await _pumpSubject(
        tester,
        song: song,
        session: session,
        showOpenCueAction: true,
        cues: const [],
      );

      expect(find.text('Hozzáadás megnyitott listához'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Másik listához adás'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tablet actions show added state when song is already in active cue',
    (tester) async {
      final song = _createSong('song-1', 'Song');
      final cue = Cue(1, 'cue-1', 'Cue', '', currentCueVersion, const []);
      final session = _createSession(
        cue: cue,
        slides: [SongSlide.from(song, viewType: SongViewType.lyrics)],
      );

      await _pumpSubject(
        tester,
        song: song,
        session: session,
        showOpenCueAction: true,
        cues: const [],
      );

      expect(find.text('Megnyitott listához adva'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Hozzáadás listához'),
        findsOneWidget,
      );
    },
  );

  testWidgets('tablet song bottom bar does not throw layout exceptions', (
    tester,
  ) async {
    final song = _createSong('song-1', 'Song');
    final otherSong = _createSong('song-2', 'Other');
    final cue = Cue(1, 'cue-1', 'Cue', '', currentCueVersion, const []);
    final session = _createSession(
      cue: cue,
      slides: [SongSlide.from(otherSong, viewType: SongViewType.lyrics)],
    );

    await _pumpTabletBottomBar(
      tester,
      song: song,
      session: session,
      cues: const [],
    );

    expect(tester.takeException(), equals(null));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'song page hides open cue action when shell uses bottom cue overlay even on wide non-desktop layouts',
    (tester) async {
      final song = _createSong('song-1', 'Song');
      final otherSong = _createSong('song-2', 'Other');
      final cue = Cue(1, 'cue-1', 'Cue', '', currentCueVersion, const []);
      final session = _createSession(
        cue: cue,
        slides: [SongSlide.from(otherSong, viewType: SongViewType.lyrics)],
      );

      await _pumpSongPageContent(
        tester,
        song: song,
        session: session,
        cues: const [],
        shellPresentation: CueShellPresentation.bottomOverlay,
        size: const Size(820, 700),
      );

      expect(find.text('Hozzáadás megnyitott listához'), findsNothing);
    },
  );

  testWidgets(
    'song page shows open cue action when shell is inline on wide non-desktop layouts',
    (tester) async {
      final song = _createSong('song-1', 'Song');
      final otherSong = _createSong('song-2', 'Other');
      final cue = Cue(1, 'cue-1', 'Cue', '', currentCueVersion, const []);
      final session = _createSession(
        cue: cue,
        slides: [SongSlide.from(otherSong, viewType: SongViewType.lyrics)],
      );

      await _pumpSongPageContent(
        tester,
        song: song,
        session: session,
        cues: const [],
        shellPresentation: CueShellPresentation.inline,
        size: const Size(820, 700),
      );

      expect(find.text('Hozzáadás megnyitott listához'), findsOneWidget);
    },
  );

  testWidgets(
    'desktop actions show added state and add hint when song is already in active cue',
    (tester) async {
      final song = _createSong('song-1', 'Song');
      final cue = Cue(1, 'cue-1', 'Cue', '', currentCueVersion, const []);
      final session = _createSession(
        cue: cue,
        slides: [SongSlide.from(song, viewType: SongViewType.lyrics)],
      );

      await _pumpSubject(
        tester,
        song: song,
        session: session,
        isDesktop: true,
        cues: const [],
      );

      expect(find.text('Megnyitott listához adva'), findsOneWidget);
      expect(find.text('Hozzáadás listához...'), findsOneWidget);
      expect(find.text('Hozzáadás megnyitott listához'), findsNothing);
    },
  );

  testWidgets(
    'desktop open cue add button adds the current song to the active cue',
    (tester) async {
      final song = _createSong('song-1', 'Song');
      final otherSong = _createSong('song-2', 'Other');
      final cue = Cue(1, 'cue-1', 'Cue', '', currentCueVersion, const []);
      final session = _createSession(
        cue: cue,
        slides: [SongSlide.from(otherSong, viewType: SongViewType.lyrics)],
      );

      final container = await _pumpSubject(
        tester,
        song: song,
        session: session,
        isDesktop: true,
        cues: const [],
      );

      await tester.tap(find.text('Hozzáadás megnyitott listához'));
      await tester.pumpAndSettle();

      final updatedSession = container.read(activeCueSessionProvider).value;

      expect(updatedSession, isA<CueSession>());
      expect(
        session.slides.whereType<SongSlide>().any(
          (slide) => slide.song.uuid == song.uuid,
        ),
        isTrue,
      );
      expect(find.text('Megnyitott listához adva'), findsOneWidget);
      expect(fakeMessenger.shownSnackBars, isNotEmpty);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
