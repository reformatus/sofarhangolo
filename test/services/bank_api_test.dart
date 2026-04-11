import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/services/http/dio_provider.dart';

import '../harness/test_harness.dart';

void main() {
  group('BankApi', () {
    late TestHarness harness;
    late RecordingHttpAdapter recorder;

    setUp(() {
      harness = TestHarness();
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

    // Add more BankApi tests here...
  });
}
