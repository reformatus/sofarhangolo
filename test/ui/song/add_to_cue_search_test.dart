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
import 'package:sofarhangolo/services/ui/messenger_service.dart';
import 'package:sofarhangolo/ui/cue/session/cue_session.dart';
import 'package:sofarhangolo/ui/cue/session/session_provider.dart';
import 'package:sofarhangolo/ui/song/add_to_cue_search.dart';
import 'package:sofarhangolo/ui/song/state.dart';

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
}) async {
  late ProviderContainer container;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
              return Center(
                child: AddToCueSearch(
                  song: song,
                  isDesktop: false,
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

    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byIcon(Icons.playlist_add), findsOneWidget);
    expect(find.byTooltip('Hozzáadás listához'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
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

    await tester.tap(find.byTooltip('Hozzáadás listához'));
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
}
