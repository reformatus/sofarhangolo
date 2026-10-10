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

/// Fetches [song]'s [fieldName] attachment bytes, or null when the song has no
/// such attachment.
///
/// The imperative counterpart of [getSongAsset]: use it where the bytes are
/// needed directly (sharing, copying) instead of watching a stream. [dio]
/// defaults to the app's shared client; tests pass a mock.
Future<Uint8List?> fetchSongAsset(
  Song song,
  String fieldName, {
  Dio? dio,
}) async {
  if (song.contentString(fieldName) == null) return null;
  final bank = await loadBankOfSong(song);
  return fetchSongAssetBytes(song, fieldName, bank: bank, dio: dio ?? appDio);
}

/// Fetches [song]'s [fieldName] attachment bytes from [bank].
///
/// Local songs resolve the attachment from the assets table. Bank songs use a
/// cached download when present; otherwise [dio] downloads it and it is cached
/// for offline reuse. [onProgress] reports 0..1 while downloading, with a
/// leading null meaning "starting".
///
/// Throws [AppError] when the attachment is missing or the download fails.
Future<Uint8List> fetchSongAssetBytes(
  Song song,
  String fieldName, {
  required Bank bank,
  required Dio dio,
  void Function(double? progress)? onProgress,
}) async {
  final contentReference = song.contentString(fieldName);
  if (contentReference == null) {
    throw ArgumentError.value(
      fieldName,
      'fieldName',
      'song has no such attachment',
    );
  }

  if (bank.access == BankAccess.local) {
    // Local songs reference their attachments with a bank-independent
    // local:// scheme stored verbatim as the asset's sourceUrl.
    final asset =
        await (db.assets.select()
              ..where((a) => a.sourceUrl.equals(contentReference)))
            .getSingleOrNull();

    if (asset == null) {
      throw AppError.from(
        StateError('Missing local song attachment: $contentReference'),
        userMessage: 'A csatolmány nem található.',
        technicalMessage:
            'Helyi dal csatolmánya nem található: $contentReference',
      );
    }
    return asset.content;
  }

  final String sourceUrl = bank.baseUrl.resolve(contentReference).toString();

  final cached =
      await (db.assets.select()..where((a) => a.sourceUrl.equals(sourceUrl)))
          .getSingleOrNull();
  if (cached != null) return cached.content;

  try {
    onProgress?.call(null);

    final response = await dio.get<List<int>>(
      sourceUrl,
      options: Options(
        responseType: ResponseType.bytes,
        sendTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 10),
      ),
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      },
    );

    final responseData = response.data;
    if (responseData == null) {
      throw StateError('Üres válasz érkezett a kottához: $sourceUrl');
    }
    final bytes = Uint8List.fromList(responseData);

    // Cache for offline reuse; a caching failure must not fail the fetch.
    unawaited(
      db.assets
          .insert()
          .insert(
            AssetsCompanion(
              songUuid: Value(song.uuid),
              fieldName: Value(fieldName),
              sourceUrl: Value(sourceUrl),
              content: Value(bytes),
            ),
          )
          .then(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              log.severe(
                'Nem sikerült menteni a letöltött kottát',
                error,
                stackTrace,
              );
            },
          ),
    );

    return bytes;
  } catch (error, stackTrace) {
    throw AppError.from(
      error,
      stackTrace: stackTrace,
      userMessage:
          'A kotta letöltése nem sikerült. Ellenőrizd a kapcsolatot, majd próbáld újra.',
      technicalMessage: 'Kotta letöltési hiba: $sourceUrl',
    );
  }
}

/// The reactive counterpart of [fetchSongAsset]: reports download progress and
/// then the bytes. Attachments that are already available (local or cached)
/// emit a single completed event.
@riverpod
Stream<AssetResult> getSongAsset(Ref ref, Song song, String fieldName) {
  final controller = StreamController<AssetResult>();

  () async {
    try {
      if (song.contentString(fieldName) == null) {
        await controller.close();
        return;
      }

      final bank = await ref.watch(bankOfSongProvider(song).future);

      final bytes = await fetchSongAssetBytes(
        song,
        fieldName,
        bank: bank,
        dio: ref.read(dioProvider),
        onProgress: (progress) =>
            controller.add((progress: progress, data: null)),
      );

      controller.add((progress: 1.0, data: bytes));
    } catch (error, stackTrace) {
      controller.addError(
        error is AppError ? error : AppError.from(error, stackTrace: stackTrace),
        stackTrace,
      );
    } finally {
      await controller.close();
    }
  }();

  return controller.stream;
}
