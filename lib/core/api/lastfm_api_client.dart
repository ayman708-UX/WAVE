import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../utils/app_logger.dart';

class LastfmApiClient {
  static String? get apiKey =>
      AppConfig.lastfmApiKey.isNotEmpty ? AppConfig.lastfmApiKey : null;
  static String? get sharedSecret =>
      AppConfig.lastfmSharedSecret.isNotEmpty ? AppConfig.lastfmSharedSecret : null;

  static Future<void> loadEnv() async {
    await AppConfig.init();
    if (apiKey != null) {
      appLogger.i('Loaded LASTFM_API_KEY');
    }
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'http://ws.audioscrobbler.com/2.0/',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  Future<List<Map<String, String>>> getSimilarTracks(
    String track,
    String artist, {
    int limit = 15,
  }) async {
    if (apiKey == null) {
      appLogger.e('Last.fm API key is missing');
      return [];
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '',
        queryParameters: <String, dynamic>{
          'method': 'track.getsimilar',
          'artist': artist,
          'track': track,
          'api_key': apiKey,
          'format': 'json',
          'limit': limit,
          'autocorrect': 1,
        },
      );

      final trackList =
          res.data?['similartracks']?['track'] as List<dynamic>?;
      if (trackList == null) return [];

      return trackList.map<Map<String, String>>((t) {
        final tMap = t as Map<String, dynamic>;
        final artistName =
            (tMap['artist'] is Map)
                ? (tMap['artist'] as Map<String, dynamic>)['name']?.toString() ??
                    ''
                : tMap['artist']?.toString() ?? '';
        final trackName = tMap['name']?.toString() ?? '';
        return {'title': trackName, 'artist': artistName};
      }).toList();
    } catch (e) {
      appLogger.e('Failed to fetch similar tracks from Last.fm: $e');
      return [];
    }
  }
}
