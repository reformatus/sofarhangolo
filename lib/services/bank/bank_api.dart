import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../data/bank/bank.dart';
import '../../data/song/song.dart';
import '../error/app_error.dart';

class BankApi {
  final Dio dio;

  const BankApi(this.dio);

  Future<List<ProtoSong>> getProtoSongs(Bank bank, {DateTime? since}) async {
    String url = '${bank.baseUrl}/songs';
    if (since != null) {
      String formattedDate = DateFormat('yyyy-MM-dd+HH:mm').format(since);
      url += '?c=$formattedDate';
    }
    final resp = await dio.get<String>(url);
    final jsonList = jsonDecode(resp.data ?? "[]") as List;

    return jsonList
        .map((e) => ProtoSong.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Song>> getDetailsForSongs(Bank bank, List<String> uuids) async {
    Uri source = Uri.parse('${bank.baseUrl}/song/${uuids.join(',')}');

    final resp = await dio.getUri<String>(source);
    try {
      var songsJson = jsonDecode(resp.data!);
      if (songsJson is List) {
        List<Song> songs = [];
        for (Map songJson in songsJson) {
          songs.add(
            Song.fromBankApiJson(
              songJson as Map<String, dynamic>,
              sourceBank: bank,
            ),
          );
        }
        return songs;
      } else {
        var song = Song.fromBankApiJson(
          songsJson as Map<String, dynamic>,
          sourceBank: bank,
        );
        return [song];
      }
    } catch (e) {
      throw AppError.from(
        e,
        userMessage: 'Hiba történt néhány dal feldolgozása közben.',
        technicalMessage: 'Error while updating songs with uuids $uuids\n$e',
      );
    }
  }

  Future<DateTime?> getRemoteLastUpdated(Bank bank) async {
    try {
      final resp = await dio.get<String>('${bank.baseUrl}/about');
      final jsonData = jsonDecode(resp.data ?? "{}") as Map<String, dynamic>;

      if (jsonData.containsKey('lastUpdated')) {
        return DateTime.parse(jsonData['lastUpdated'] as String);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
