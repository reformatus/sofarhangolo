import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/bank/bank.dart';
import '../../data/database.dart';
import '../../data/log/logger.dart';
import '../../data/song/song.dart';
import '../bank/bank_of_song.dart';
import '../error/app_error.dart';
import '../http/dio_provider.dart';

part 'get_song_asset.g.dart';

typedef AssetResult = ({double? progress, Uint8List? data});

@riverpod
Stream<AssetResult> getSongAsset(
  Ref ref,
  Song song,
  String fieldName,
  //int fieldIndex, // TODO handle multi-file fields?
) {
  final controller = StreamController<AssetResult>();

  () async {
    final bank = await ref.watch(bankOfSongProvider(song).future);
    final contentReference = song.contentMap[fieldName];
    if (contentReference == null) {
      await controller.close();
      return;
    }

    if (bank.access == BankAccess.local) {
      // Local songs reference their attachments with a bank-independent
      // local:// scheme stored verbatim as the asset's sourceUrl.
      final asset =
          await (db.assets.select()
                ..where((a) => a.sourceUrl.equals(contentReference)))
              .getSingleOrNull();

      if (asset != null) {
        controller.add((progress: 1.0, data: asset.content));
      } else {
        controller.addError(
          AppError.from(
            StateError('Missing local song attachment: $contentReference'),
            userMessage: 'A csatolmány nem található.',
            technicalMessage:
                'Helyi dal csatolmánya nem található: $contentReference',
          ),
        );
      }
      await controller.close();
      return;
    }

    final String sourceUrl = bank.baseUrl
        .resolve(contentReference)
        .toString();

    final asset =
        await (db.assets.select()..where((a) => a.sourceUrl.equals(sourceUrl)))
            .getSingleOrNull();

    if (asset != null) {
      controller.add((progress: 1.0, data: asset.content));
      await controller.close();
    } else {
      // Download the asset with progress updates
      try {
        controller.add((progress: null, data: null));

        final dio = ref.read(dioProvider);
        final response = await dio.get<List<int>>(
          sourceUrl,
          options: Options(
            responseType: ResponseType.bytes,
            sendTimeout: Duration(seconds: 3),
            receiveTimeout: Duration(seconds: 10),
          ),
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = (received / total).clamp(0.0, 1.0);
              controller.add((progress: progress, data: null));
            }
          },
        );

        final responseData = response.data;
        if (responseData == null) {
          throw StateError('Üres válasz érkezett a kottához: $sourceUrl');
        }
        final bytes = Uint8List.fromList(responseData);

        // Display the content right away; caching it below must not
        // block showing the sheet music.
        controller.add((progress: 1.0, data: bytes));

        // Save the downloaded asset to the database for offline reuse.
        // Errors surface through the logging-based snackbar convention.
        unawaited(
          db.assets.insert().insert(
            AssetsCompanion(
              songUuid: Value(song.uuid),
              fieldName: Value(fieldName),
              sourceUrl: Value(sourceUrl),
              content: Value(bytes),
            ),
          ).then(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              log.severe('Nem sikerült menteni a letöltött kottát', error, stackTrace);
            },
          ),
        );
      } catch (error, stackTrace) {
        controller.addError(
          AppError.from(
            error,
            stackTrace: stackTrace,
            userMessage:
                'A kotta letöltése nem sikerült. Ellenőrizd a kapcsolatot, majd próbáld újra.',
            technicalMessage: 'Kotta letöltési hiba: $sourceUrl',
          ),
          stackTrace,
        );
      } finally {
        await controller.close();
      }
    }
  }();

  return controller.stream;
}
