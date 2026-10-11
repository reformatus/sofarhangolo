import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/database.dart';
import 'package:sofarhangolo/services/bank/banks.dart';

import '../harness/test_database.dart';
import '../harness/test_harness.dart' show waitForProviderValue;

Future<void> insertBank(String uuid, String name) async {
  await db
      .into(db.banks)
      .insert(
        BanksCompanion.insert(
          uuid: uuid,
          name: name,
          baseUrl: Value(Uri.parse('https://$uuid.example.com')),
          parallelUpdateJobs: 1,
          amountOfSongsInRequest: 10,
          noCms: false,
          songFields: {},
          isEnabled: true,
          isOfflineMode: false,
        ),
      );
}

void main() {
  group('bankByUuid', () {
    late LyricDatabase testDb;

    setUp(() async {
      testDb = createTestDatabase();
      db = testDb;
      await insertBank('bank-1', 'First Bank');
      await insertBank('bank-2', 'Second Bank');
    });

    tearDown(() async {
      await testDb.close();
    });

    Future<ProviderContainer> loadedContainer() async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Wait for the first banks emission so the lookup sees loaded data.
      await waitForProviderValue(container, watchAllBanksProvider);
      return container;
    }

    test('resolves the bank with a matching uuid', () async {
      final container = await loadedContainer();

      expect(container.read(bankByUuidProvider('bank-1'))!.name, 'First Bank');
      expect(container.read(bankByUuidProvider('bank-2'))!.name, 'Second Bank');
    });

    test('null for an unknown uuid', () async {
      final container = await loadedContainer();

      expect(container.read(bankByUuidProvider('nope')), isNull);
    });

    test('null for a null uuid (songs without a source bank)', () async {
      final container = await loadedContainer();

      expect(container.read(bankByUuidProvider(null)), isNull);
    });

    test('follows bank table changes', () async {
      final container = await loadedContainer();
      expect(container.read(bankByUuidProvider('bank-3')), isNull);

      final appeared = Completer<Bank>();
      container.listen<Bank?>(bankByUuidProvider('bank-3'), (previous, next) {
        if (next != null && !appeared.isCompleted) appeared.complete(next);
      });
      await insertBank('bank-3', 'Third Bank');

      final bank = await appeared.future.timeout(const Duration(seconds: 5));
      expect(bank.name, 'Third Bank');
    });
  });
}
