import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/database.dart';
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
    if (bank == null || contentReference == null) {
      // Local songs and songs whose bank is gone have no fetchable assets.
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

        // Save the downloaded asset to the database
        await db.assets.insert().insert(
          AssetsCompanion(
            songUuid: Value(song.uuid),
            fieldName: Value(fieldName),
            sourceUrl: Value(sourceUrl),
            content: Value(Uint8List.fromList(responseData)),
          ),
        );

        // Add the final value
        controller.add((progress: 1.0, data: Uint8List.fromList(responseData)));
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
