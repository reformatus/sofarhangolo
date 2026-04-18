import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/song/lyrics/format.dart';
import 'package:sofarhangolo/services/http/dio_provider.dart';
import 'package:sofarhangolo/services/bank/bank_api.dart';

import '../harness/test_harness.dart';

void main() {
  group('BankApi', () {
    late TestHarness harness;
    late RecordingHttpAdapter recorder;
    late Bank bank;

    setUp(() {
      harness = TestHarness();
      bank = Bank(
        1,
        'bank-1',
        null,
        null,
        'Test Bank',
        null,
        null,
        null,
        null,
        Uri.parse('https://example.com/api'),
        1,
        1,
        false,
        {},
        true,
        false,
        null,
        null,
        null,
      );
      recorder = RecordingHttpAdapter(
        responseBuilder: (options) {
          // Return different responses based on the request path
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Test Song"}]',
              200,
            );
          }
          if (options.path.contains('/about')) {
            return ResponseBody.fromString(
              '{"lastUpdated":"2025-01-01T00:00:00Z"}',
              200,
            );
          }
          return ResponseBody.fromString('{}', 200);
        },
      );
      harness.mockDio.httpClientAdapter = recorder;
    });

    tearDown(() {
      harness.dispose();
    });

    test('dioProvider returns mock dio from harness', () {
      final dio = harness.container.read(dioProvider);
      expect(dio, isA<Dio>());
    });

    test('requests are recorded for assertions', () async {
      final dio = harness.container.read(dioProvider);
      await dio.get('https://example.com/api/songs');

      expect(recorder.requests, hasLength(1));
      expect(recorder.requests.first.path, contains('/songs'));
    });

    test('getProtoSongs decodes escaped titles', () async {
      recorder = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/songs')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Tom &amp; Jerry"}]',
              200,
            );
          }
          return ResponseBody.fromString('[]', 200);
        },
      );
      harness.mockDio.httpClientAdapter = recorder;

      final songs = await BankApi(harness.mockDio).getProtoSongs(bank);

      expect(songs, hasLength(1));
      expect(songs.first.title, equals('Tom & Jerry'));
    });

    test('getDetailsForSongs decodes lyrics title and metadata fields', () async {
      recorder = RecordingHttpAdapter(
        responseBuilder: (options) {
          if (options.path.contains('/song/song-1')) {
            return ResponseBody.fromString(
              '[{"uuid":"song-1","title":"Tom &amp; Jerry","lyrics":"[V1]\\n A &amp; B","lyrics_format":"opensong","composer":"John &amp; Jane","pdf_title":"Lead &quot;Sheet&quot;"}]',
              200,
            );
          }
          return ResponseBody.fromString('[]', 200);
        },
      );
      harness.mockDio.httpClientAdapter = recorder;

      final songs = await BankApi(harness.mockDio).getDetailsForSongs(bank, [
        'song-1',
      ]);

      expect(songs, hasLength(1));
      expect(songs.first.title, equals('Tom & Jerry'));
      expect(songs.first.lyrics, equals('[V1]\n A & B'));
      expect(songs.first.lyricsFormat, equals(LyricsFormat.opensong));
      expect(songs.first.contentMap['composer'], equals('John & Jane'));
      expect(songs.first.contentMap['pdf_title'], equals('Lead "Sheet"'));
    });
  });
}
