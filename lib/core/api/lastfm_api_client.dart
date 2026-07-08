import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../utils/app_logger.dart';

class LastfmApiClient {
  static String? apiKey;
  static String? sharedSecret;

  static Future<void> loadEnv() async {
    try {
      final content = await rootBundle.loadString('.env');
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join('=').trim();
          if (key == 'LASTFM_API_KEY') {
            apiKey = value;
            appLogger.i('Loaded LASTFM_API_KEY');
          } else if (key == 'LASTFM_SHARED_SECRET') {
            sharedSecret = value;
          }
        }
      }
    } catch (e) {
      appLogger.w('Could not load .env file for Last.fm: $e');
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

      final data = res.data;
      if (data != null &&
          data['similartracks'] != null &&
          data['similartracks']['track'] is List) {
        final tracks = data['similartracks']['track'] as List;
        return tracks.map((t) {
          return {
            'name': t['name']?.toString() ?? '',
            'artist': t['artist']?['name']?.toString() ?? '',
          };
        }).toList();
      }
    } catch (e) {
      appLogger.e('Failed to fetch similar tracks from Last.fm: $e');
    }
    return [];
  }
}
