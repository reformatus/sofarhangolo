import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/database.dart';

import '../harness/test_harness.dart';

void main() {
  group('Database operations', () {
    late LyricDatabase testDb;

    setUp(() async {
      testDb = createTestDatabase();
    });

    tearDown(() async {
      await testDb.close();
    });

    test('can insert and query banks', () async {
      // Insert a test bank
      await testDb
          .into(testDb.banks)
          .insert(
            BanksCompanion.insert(
              uuid: 'test-bank-uuid',
              name: 'Test Bank',
              baseUrl: Uri.parse('https://example.com/api'),
              parallelUpdateJobs: 2,
              amountOfSongsInRequest: 10,
              noCms: false,
              songFields: {},
              isEnabled: true,
              isOfflineMode: false,
            ),
          );

      // Query it back
      final banks = await testDb.select(testDb.banks).get();
      expect(banks, hasLength(1));
      expect(banks.first.name, equals('Test Bank'));
    });

    test('clearAllTables removes all data', () async {
      // Insert some data
      await testDb
          .into(testDb.banks)
          .insert(
            BanksCompanion.insert(
              uuid: 'test-bank',
              name: 'Test',
              baseUrl: Uri.parse('https://example.com'),
              parallelUpdateJobs: 1,
              amountOfSongsInRequest: 5,
              noCms: false,
              songFields: {},
              isEnabled: true,
              isOfflineMode: false,
            ),
          );

      // Clear and verify
      await testDb.clearAllTables();
      final banks = await testDb.select(testDb.banks).get();
      expect(banks, isEmpty);
    });
  });
}
