import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../config/config.dart';
import '../../data/bank/bank.dart';
import '../../data/database.dart';
import '../../data/log/logger.dart';
import '../error/app_error.dart';
import 'from_uuid.dart';

Future<Set<String>> updateBanks(Dio dio) async {
  late List protoBanks;
  try {
    protoBanks = (await dio.getUri<List>(
      Uri.parse('${appConfig.apiRoot}/banks/'),
    )).data!;
  } catch (e, s) {
    throw AppError.from(
      e,
      stackTrace: s,
      userMessage:
          'Nem sikerült lekérni az elérhető daltárakat. Próbáld újra később.',
    );
  }

  final availableBankUuids = <String>{};

  for (final protoBank in protoBanks) {
    late Map details;

    try {
      details = (await dio.getUri<Map>(
        Uri.parse('${protoBank['api']}/about/'),
      )).data!;
    } catch (e, s) {
      log.warning(
        kIsWeb
            ? 'A(z) ${protoBank['name']} daltár böngészőből nem érhető el, ezért most kihagyjuk.'
            : 'Nem sikerült lekérni az adatokat: ${protoBank['name']}.',
        e,
        s,
      );
      continue;
    }

    Bank? existingBank = await dbWatchBankWithUuid(details['uuid']).first;

    Uint8List? logo;
    if (details['logo'] != null &&
        (existingBank == null || existingBank.logo == null)) {
      try {
        logo = (await dio.get<Uint8List>(
          details['logo'],
          options: Options(responseType: ResponseType.bytes),
        )).data;
      } catch (_) {}
    } else {
      logo = existingBank?.logo;
    }
    Uint8List? tinyLogo;
    if (details['tinyLogo'] != null &&
        (existingBank == null || existingBank.tinyLogo == null)) {
      try {
        tinyLogo = (await dio.get<Uint8List>(
          details['tinyLogo'],
          options: Options(responseType: ResponseType.bytes),
        )).data;
      } catch (_) {}
    } else {
      tinyLogo = existingBank?.tinyLogo;
    }

    bool isEnabled = false;
    if (existingBank != null) {
      isEnabled = existingBank.isEnabled;
    } else {
      isEnabled = protoBank['defaultEnabled'] ?? false;
    }

    bool offlineMode = existingBank?.isOfflineMode ?? false;

    BanksCompanion banksCompanion = BanksCompanion(
      id: Value.absentIfNull(existingBank?.id),
      uuid: Value(details['uuid']!),
      baseUrl: Value(Uri.parse(protoBank['api'])),
      logo: Value.absentIfNull(logo),
      tinyLogo: Value.absentIfNull(tinyLogo),
      name: Value(details['name']!),
      description: Value.absentIfNull(details['description']),
      legal: Value.absentIfNull(details['legal']),
      aboutLink: Value.absentIfNull(details['aboutLink']),
      contactEmail: Value.absentIfNull(details['contactEmail']),
      parallelUpdateJobs: Value(details['parallelUpdateJobs']!),
      amountOfSongsInRequest: Value(details['amountOfSongsInRequest']!),
      noCms: Value(details['noCms'] ?? false),
      songFields: Value(details['songFields']),
      isEnabled: Value(isEnabled),
      isOfflineMode: Value(offlineMode),
      lastUpdated: Value.absent(),
      failedSongUuids: Value.absent(),
      totalSongsInBank: Value.absent(),
    );

    await db.into(db.banks).insertOnConflictUpdate(banksCompanion);
    availableBankUuids.add(details['uuid'] as String);
  }

  return availableBankUuids;
}
