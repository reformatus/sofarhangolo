import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/ui/song/lyrics/view.dart';

import '../../../harness/test_harness.dart';

/// Captures the URLs the report action hands to the platform, by mocking
/// `url_launcher`'s method channel (its platform interface is a transitive
/// dependency, so the channel is the stable seam to fake here).
class _FakeUrlLauncher {
  static const MethodChannel _channel = MethodChannel(
    'plugins.flutter.io/url_launcher',
  );

  final List<String> launched = [];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'canLaunch':
              return true;
            case 'launch':
              launched.add(
                (call.arguments as Map<Object?, Object?>)['url']! as String,
              );
              return true;
          }
          return null;
        });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

void main() {
  late LyricDatabase testDb;
  late TestHarness harness;
  late _FakeUrlLauncher launcher;

  setUp(() async {
    testDb = createTestDatabase();
    db = testDb;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    harness = TestHarness();
    launcher = _FakeUrlLauncher();
    launcher.install();
  });

  tearDown(() async {
    launcher.remove();
    harness.dispose();
    await testDb.close();
  });

  Future<void> insertBank({
    required String uuid,
    required String name,
    String? contactEmail,
  }) {
    return db
        .into(db.banks)
        .insert(
          BanksCompanion.insert(
            uuid: uuid,
            name: name,
            parallelUpdateJobs: 1,
            amountOfSongsInRequest: 1,
            noCms: false,
            songFields: {},
            isEnabled: true,
            isOfflineMode: false,
            contactEmail: Value(contactEmail),
          ),
        );
  }

  Song songWithoutLyrics({required String? sourceBank}) => Song(
    uuid: 'song-1',
    title: 'A dal',
    lyrics: null,
    keyField: const [],
    contentMap: const {},
    sourceBank: sourceBank,
  );

  Future<void> pumpLyricsView(WidgetTester tester, Song song) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          home: Scaffold(body: LyricsView(song)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('reports a song without lyrics to its bank', (tester) async {
    await insertBank(
      uuid: 'bank-1',
      name: 'Daltár',
      contactEmail: 'hiba@daltar.hu',
    );

    await pumpLyricsView(
      tester,
      songWithoutLyrics(sourceBank: 'bank-1'),
    );

    expect(find.text('A dalhoz nem tartozik dalszöveg!'), findsOneWidget);
    expect(find.text('Hibajelentés'), findsOneWidget);

    await tester.tap(find.text('Hibajelentés'));
    await tester.pumpAndSettle();

    // The bank's own address gets the report, not the app's feedback address.
    expect(launcher.launched, hasLength(1));
    final reported = launcher.launched.single;
    expect(reported, startsWith('mailto:hiba@daltar.hu'));
    // The song's title travels in the (percent-encoded) subject.
    expect(Uri.decodeFull(reported), contains('A dal'));
  });

  testWidgets('hides the report action for a local song', (tester) async {
    await insertBank(uuid: localBankUuid, name: 'Helyi dalok');

    await pumpLyricsView(
      tester,
      songWithoutLyrics(sourceBank: localBankUuid),
    );

    expect(find.text('A dalhoz nem tartozik dalszöveg!'), findsOneWidget);
    expect(find.text('Hibajelentés'), findsNothing);
    expect(launcher.launched, isEmpty);
  });

  testWidgets('hides the report action for a song with no bank', (
    tester,
  ) async {
    await pumpLyricsView(tester, songWithoutLyrics(sourceBank: null));

    expect(find.text('A dalhoz nem tartozik dalszöveg!'), findsOneWidget);
    expect(find.text('Hibajelentés'), findsNothing);
  });

  testWidgets('hides the report action for a bank with no contact address', (
    tester,
  ) async {
    await insertBank(uuid: 'bank-2', name: 'Néma daltár');

    await pumpLyricsView(
      tester,
      songWithoutLyrics(sourceBank: 'bank-2'),
    );

    expect(find.text('A dalhoz nem tartozik dalszöveg!'), findsOneWidget);
    expect(find.text('Hibajelentés'), findsNothing);
  });
}
