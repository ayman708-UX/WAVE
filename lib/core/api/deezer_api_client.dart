import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../utils/app_logger.dart';
import 'models/deezer_album.dart';
import 'models/deezer_artist.dart';
import 'models/deezer_genre.dart';
import 'models/deezer_playlist.dart';
import 'models/deezer_track.dart';
import 'models/deezer_user.dart';

/// Thin wrapper over the public Deezer API (`https://api.deezer.com`).
///
/// All methods accept an optional [CancelToken] so callers can cancel the
/// request when their widget disposes.
class DeezerApiClient {
  static String? get proxyUrl =>
      AppConfig.deezerProxyUrl.isNotEmpty ? AppConfig.deezerProxyUrl : null;
  static bool useProxy = false;

  static Future<void> loadEnv() async {
    await AppConfig.init();
    if (proxyUrl != null) {
      appLogger.i('Loaded DEEZER_PROXY_URL: $proxyUrl');
    }
  }

  static Future<void> checkGeoRestriction() async {
    try {
      final checkDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      final res = await checkDio.get<dynamic>(
        'https://api.deezer.com/search?q=believer',
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map;
        if (data['error'] != null) {
          appLogger.w(
            'Deezer API returned geo-restriction error: ${data['error']}. Activating proxy.',
          );
          useProxy = true;
        } else if (data['data'] is List && (data['data'] as List).isEmpty) {
          appLogger.w(
            'Deezer API returned empty results (possible restriction). Activating proxy.',
          );
          useProxy = true;
        } else {
          appLogger.i('Deezer API health check succeeded. Proxy disabled.');
          useProxy = false;
        }
      } else {
        appLogger.w(
          'Deezer API health check returned code ${res.statusCode}. Activating proxy.',
        );
        useProxy = true;
      }
    } catch (e) {
      appLogger.w('Deezer API health check failed: $e. Activating proxy.');
      useProxy = true;
    }
  }

  static dynamic _proxyJsonUrls(dynamic json, String proxyUrl) {
    if (json is Map) {
      return json.map(
        (key, value) =>
            MapEntry(key.toString(), _proxyJsonUrls(value, proxyUrl)),
      );
    } else if (json is List) {
      return json.map((item) => _proxyJsonUrls(item, proxyUrl)).toList();
    } else if (json is String) {
      if (json.startsWith('http') &&
          (json.contains('api.deezer.com') || json.contains('dzcdn.net')) &&
          !json.startsWith(proxyUrl)) {
        return '$proxyUrl${Uri.encodeComponent(json)}';
      }
      return json;
    }
    return json;
  }

  DeezerApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.deezer.com',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: <String, String>{'Accept': 'application/json'},
              responseType: ResponseType.json,
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (useProxy && proxyUrl != null && proxyUrl!.isNotEmpty) {
            final fullTargetUrl = options.uri.toString();
            if (!fullTargetUrl.startsWith(proxyUrl!)) {
              options.path = '$proxyUrl${Uri.encodeComponent(fullTargetUrl)}';
              options.queryParameters = {};
              appLogger.d(
                'Proxying request: $fullTargetUrl -> ${options.path}',
              );
            }
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (useProxy && proxyUrl != null && proxyUrl!.isNotEmpty) {
            if (response.data != null) {
              response.data = _proxyJsonUrls(response.data, proxyUrl!);
            }
          }
          handler.next(response);
        },
        onError: (err, handler) {
          appLogger.w(
            'Deezer error: ${err.requestOptions.uri} -> ${err.message}',
          );
          handler.next(err);
        },
      ),
    );
  }

  final Dio _dio;

  // ---------------------------------------------------------------------------
  // Charts & editorial
  // ---------------------------------------------------------------------------

  /// Aggregated trending tracks, albums, artists and playlists.
  Future<Map<String, dynamic>> getChart({CancelToken? cancelToken}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/chart',
      cancelToken: cancelToken,
    );
    return res.data ?? <String, dynamic>{};
  }

  Future<List<DeezerTrack>> getChartTracks({
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/chart/0/tracks',
      queryParameters: <String, dynamic>{'limit': limit},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerTrack.fromJson);
  }

  Future<List<DeezerAlbum>> getChartAlbums({
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/chart/0/albums',
      queryParameters: <String, dynamic>{'limit': limit},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerAlbum.fromJson);
  }

  Future<List<DeezerArtist>> getChartArtists({
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/chart/0/artists',
      queryParameters: <String, dynamic>{'limit': limit},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerArtist.fromJson);
  }

  Future<List<DeezerPlaylist>> getChartPlaylists({
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/chart/0/playlists',
      queryParameters: <String, dynamic>{'limit': limit},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerPlaylist.fromJson);
  }

  Future<Map<String, dynamic>> getEditorialSelection({
    int editorialId = 0,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/editorial/$editorialId/selection',
      cancelToken: cancelToken,
    );
    return res.data ?? <String, dynamic>{};
  }

  Future<List<DeezerAlbum>> getNewReleases({
    int editorialId = 0,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/editorial/$editorialId/releases',
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerAlbum.fromJson);
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<List<DeezerTrack>> searchTracks(
    String query, {
    int limit = 25,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/search',
      queryParameters: <String, dynamic>{'q': query, 'limit': limit},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerTrack.fromJson);
  }

  Future<List<DeezerArtist>> searchArtists(
    String query, {
    int limit = 25,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/search/artist',
      queryParameters: <String, dynamic>{'q': query, 'limit': limit},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerArtist.fromJson);
  }

  Future<List<DeezerAlbum>> searchAlbums(
    String query, {
    int limit = 25,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/search/album',
      queryParameters: <String, dynamic>{'q': query, 'limit': limit},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerAlbum.fromJson);
  }

  Future<List<DeezerPlaylist>> searchPlaylists(
    String query, {
    int limit = 25,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/search/playlist',
      queryParameters: <String, dynamic>{'q': query, 'limit': limit},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerPlaylist.fromJson);
  }

  // ---------------------------------------------------------------------------
  // Detail endpoints
  // ---------------------------------------------------------------------------

  Future<DeezerTrack> getTrack(int id, {CancelToken? cancelToken}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/track/$id',
      cancelToken: cancelToken,
    );
    return DeezerTrack.fromJson(res.data ?? <String, dynamic>{});
  }

  Future<DeezerAlbum> getAlbum(int id, {CancelToken? cancelToken}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/album/$id',
      cancelToken: cancelToken,
    );
    return DeezerAlbum.fromJson(res.data ?? <String, dynamic>{});
  }

  Future<List<DeezerTrack>> getAlbumTracks(
    int id, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/album/$id/tracks',
      queryParameters: <String, dynamic>{'limit': 2000},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerTrack.fromJson);
  }

  Future<DeezerArtist> getArtist(int id, {CancelToken? cancelToken}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/artist/$id',
      cancelToken: cancelToken,
    );
    return DeezerArtist.fromJson(res.data ?? <String, dynamic>{});
  }

  Future<List<DeezerTrack>> getArtistTopTracks(
    int id, {
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/artist/$id/top',
      queryParameters: <String, dynamic>{'limit': limit},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerTrack.fromJson);
  }

  Future<List<DeezerAlbum>> getArtistAlbums(
    int id, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/artist/$id/albums',
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerAlbum.fromJson);
  }

  Future<List<DeezerArtist>> getRelatedArtists(
    int id, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/artist/$id/related',
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerArtist.fromJson);
  }

  Future<DeezerPlaylist> getPlaylist(int id, {CancelToken? cancelToken}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/playlist/$id',
      cancelToken: cancelToken,
    );
    return DeezerPlaylist.fromJson(res.data ?? <String, dynamic>{});
  }

  Future<List<DeezerTrack>> getPlaylistTracks(
    int id, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/playlist/$id/tracks',
      queryParameters: <String, dynamic>{'limit': 2000},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerTrack.fromJson);
  }

  // ---------------------------------------------------------------------------
  // User endpoints
  // ---------------------------------------------------------------------------

  Future<DeezerUser> getUser(int id, {CancelToken? cancelToken}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/user/$id',
      cancelToken: cancelToken,
    );
    return DeezerUser.fromJson(res.data ?? <String, dynamic>{});
  }

  Future<List<DeezerPlaylist>> getUserPlaylists(
    int id, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/user/$id/playlists',
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerPlaylist.fromJson);
  }

  Future<List<DeezerTrack>> getUserTracks(
    int id, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/user/$id/tracks',
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerTrack.fromJson);
  }

  Future<List<DeezerAlbum>> getUserAlbums(
    int id, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/user/$id/albums',
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerAlbum.fromJson);
  }

  Future<List<DeezerArtist>> getUserArtists(
    int id, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/user/$id/artists',
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerArtist.fromJson);
  }

  // ---------------------------------------------------------------------------
  // Genres & radio
  // ---------------------------------------------------------------------------

  Future<List<DeezerGenre>> getGenres({CancelToken? cancelToken}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/genre',
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerGenre.fromJson);
  }

  Future<List<DeezerArtist>> getGenreArtists(
    int genreId, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/genre/$genreId/artists',
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerArtist.fromJson);
  }

  Future<List<DeezerTrack>> getGenreRadioTracks(
    int genreId, {
    CancelToken? cancelToken,
  }) async {
    // Deezer doesn't expose a `/radio/genre/{id}/tracks` endpoint — the
    // closest equivalent is the per-genre chart, which returns ~100 curated
    // tracks per genre.
    final res = await _dio.get<Map<String, dynamic>>(
      '/chart/$genreId/tracks',
      queryParameters: <String, dynamic>{'limit': 100},
      cancelToken: cancelToken,
    );
    return _mapList(res.data, DeezerTrack.fromJson);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<T> _mapList<T>(
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (body != null && body.containsKey('error')) {
      appLogger.e('Deezer API returned an error body: ${body['error']}');
    }
    final raw = body?['data'];
    if (raw is! List) return <T>[];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((item) {
          try {
            return fromJson(Map<String, dynamic>.from(item));
          } catch (e) {
            appLogger.w('Error parsing Deezer item: $e\nItem: $item');
            return null;
          }
        })
        .whereType<T>()
        .toList(growable: false);
  }
}

final deezerApiClientProvider = Provider<DeezerApiClient>((ref) {
  return DeezerApiClient();
});
