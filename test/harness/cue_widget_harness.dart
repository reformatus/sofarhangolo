import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/cue/cue.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/transpose.dart';
import 'package:sofarhangolo/ui/cue/session/cue_session.dart';
import 'package:sofarhangolo/ui/cue/session/session_provider.dart';
import 'package:sofarhangolo/ui/cue/widgets/actions_drawer.dart';
import 'package:sofarhangolo/ui/cue/widgets/slide_view.dart';
import 'package:sofarhangolo/ui/song/state.dart';

import 'test_harness.dart';

const cueHarnessCurrentSlideLabelKey = ValueKey('cue-harness-current-slide');
const cueHarnessPreviousButtonKey = ValueKey('cue-harness-previous');
const cueHarnessNextButtonKey = ValueKey('cue-harness-next');

ValueKey<String> cueHarnessJumpButtonKey(String slideUuid) {
  return ValueKey('cue-harness-jump-$slideUuid');
}

class CueSongFixture {
  const CueSongFixture({
    required this.songUuid,
    required this.slideUuid,
    required this.title,
    required this.lyrics,
    this.viewType = SongViewType.lyrics,
    this.transpose,
    this.hasSvg = false,
    this.hasPdf = false,
    this.comment,
  });

  final String songUuid;
  final String slideUuid;
  final String title;
  final String lyrics;
  final SongViewType viewType;
  final SongTranspose? transpose;
  final bool hasSvg;
  final bool hasPdf;
  final String? comment;

  Map<String, dynamic> toSongJson() {
    return {
      'uuid': songUuid,
      'title': title,
      'lyrics': lyrics,
      'lyricsFormat': 'opensong',
      'key': 'C-major',
      if (hasSvg) 'svg': '/$songUuid.svg',
      if (hasPdf) 'pdf': '/$songUuid.pdf',
    };
  }

  SongSlide toSlide(Song song) {
    return SongSlide(
      slideUuid,
      song,
      comment,
      viewType: viewType,
      transpose: transpose,
    );
  }
}

class CueWidgetHarness {
  CueWidgetHarness({required this.testHarness});

  final TestHarness testHarness;

  ProviderContainer get container => testHarness.container;

  CueSession get session => container.read(activeCueSessionProvider).value!;

  SongSlide get currentSongSlide => session.currentSlide! as SongSlide;

  void navigate(int offset) {
    container.read(activeCueSessionProvider.notifier).navigate(offset);
  }

  void jumpToSlide(String slideUuid) {
    container.read(activeCueSessionProvider.notifier).goToSlide(slideUuid);
  }

  void addUnknownSlide(String slideUuid) {
    container
        .read(activeCueSessionProvider.notifier)
        .addSlide(
          UnknownTypeSlide(
            {'slideType': 'unknown', 'uuid': slideUuid, 'comment': null},
            slideUuid,
            null,
          ),
        );
  }

  Future<void> flushWrites() {
    return container.read(activeCueSessionProvider.notifier).flushWrites();
  }
}

Future<Bank> insertCueHarnessBank({
  String uuid = 'bank-1',
  Uri? baseUrl,
}) async {
  await db
      .into(db.banks)
      .insert(
        BanksCompanion.insert(
          uuid: uuid,
          name: 'Cue Harness Bank',
          baseUrl: baseUrl ?? Uri.parse('https://example.com/assets/'),
          parallelUpdateJobs: 1,
          amountOfSongsInRequest: 1,
          noCms: false,
          songFields: {},
          isEnabled: true,
          isOfflineMode: false,
        ),
      );

  return (db.select(
    db.banks,
  )..where((bank) => bank.uuid.equals(uuid))).getSingle();
}

Future<Song> insertCueHarnessSong({
  required CueSongFixture fixture,
  required Bank bank,
}) async {
  final song = Song.fromBankApiJson(fixture.toSongJson(), sourceBank: bank);
  await db.into(db.songs).insert(song, mode: InsertMode.insertOrReplace);
  return song;
}

Future<Cue> insertCueHarnessCue({
  required String cueUuid,
  required List<CueSongFixture> fixtures,
  Bank? bank,
  String title = 'Cue Harness Cue',
  String description = 'Cue widget harness fixture',
}) async {
  final resolvedBank = bank ?? await insertCueHarnessBank();
  final songs = <Song>[];

  for (final fixture in fixtures) {
    songs.add(await insertCueHarnessSong(fixture: fixture, bank: resolvedBank));
  }

  final slides = <Slide>[
    for (var index = 0; index < fixtures.length; index += 1)
      fixtures[index].toSlide(songs[index]),
  ];

  return db
      .into(db.cues)
      .insertReturning(
        CuesCompanion(
          id: const Value.absent(),
          uuid: Value(cueUuid),
          title: Value(title),
          description: Value(description),
          cueVersion: Value(currentCueVersion),
          content: Value(Cue.getContentMapFromSlides(slides)),
        ),
      );
}

void configureCueHarnessSvgResponse(
  TestHarness harness, {
  String svgLabel = 'Harness SVG',
}) {
  final svgBytes = Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80">'
      '<rect width="120" height="80" fill="white"/>'
      '<text x="10" y="45" fill="black">$svgLabel</text>'
      '</svg>',
    ),
  );

  harness.mockDio.httpClientAdapter = MockHttpAdapter(
    onRequest: (_) => ResponseBody.fromBytes(
      svgBytes,
      200,
      headers: {
        Headers.contentTypeHeader: ['image/svg+xml'],
      },
    ),
  );
}

Future<CueWidgetHarness> pumpCueWidgetHarness(
  WidgetTester tester, {
  required TestHarness testHarness,
  required String cueUuid,
  String? initialSlideUuid,
}) async {
  await testHarness.container
      .read(activeCueSessionProvider.notifier)
      .load(cueUuid, initialSlideUuid: initialSlideUuid);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: testHarness.container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const _CueHarnessCurrentSlideLabel(),
                      const Divider(height: 1),
                      Expanded(child: SlideView()),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                const SizedBox(width: 280, child: ActionsDrawer()),
                const VerticalDivider(width: 1),
                const SizedBox(width: 220, child: _CueHarnessJumpPanel()),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();

  return CueWidgetHarness(testHarness: testHarness);
}

class _CueHarnessCurrentSlideLabel extends ConsumerWidget {
  const _CueHarnessCurrentSlideLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSlideUuid = ref.watch(
      activeCueSessionProvider.select(
        (sessionAsync) => sessionAsync.value?.currentSlideUuid,
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          IconButton.filledTonal(
            key: cueHarnessPreviousButtonKey,
            onPressed: () {
              ref.read(activeCueSessionProvider.notifier).navigate(-1);
            },
            icon: const Icon(Icons.navigate_before),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'current:${currentSlideUuid ?? '-'}',
              key: cueHarnessCurrentSlideLabelKey,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            key: cueHarnessNextButtonKey,
            onPressed: () {
              ref.read(activeCueSessionProvider.notifier).navigate(1);
            },
            icon: const Icon(Icons.navigate_next),
          ),
        ],
      ),
    );
  }
}

class _CueHarnessJumpPanel extends ConsumerWidget {
  const _CueHarnessJumpPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slides = ref.watch(
      activeCueSessionProvider.select(
        (sessionAsync) => sessionAsync.value?.slides ?? const <Slide>[],
      ),
    );

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Outside Jump', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final slide in slides)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonal(
                  key: cueHarnessJumpButtonKey(slide.uuid),
                  onPressed: () {
                    ref
                        .read(activeCueSessionProvider.notifier)
                        .goToSlide(slide.uuid);
                  },
                  child: Text(slide.title),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
