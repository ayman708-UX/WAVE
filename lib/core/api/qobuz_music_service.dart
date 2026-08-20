import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/deezer_track.dart';
import '../utils/app_logger.dart';

class QobuzTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final String? isrc;
  final String? audioQuality;
  final String? artworkUrl;
  final String? format;

  QobuzTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
    this.isrc,
    this.audioQuality,
    this.artworkUrl,
    this.format,
  });

  factory QobuzTrack.fromJson(Map<String, dynamic> json) {
    return QobuzTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Track',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      album: json['album']?.toString() ?? 'Single',
      durationSeconds: int.tryParse(json['duration']?.toString() ?? '') ?? 0,
      isrc: json['isrc']?.toString(),
      audioQuality: json['audioQuality']?.toString() ?? json['quality']?.toString(),
      artworkUrl: json['artworkURL']?.toString() ?? json['artworkUrl']?.toString(),
      format: json['format']?.toString() ?? 'flac',
    );
  }
}

class QobuzMusicService {
  static final QobuzMusicService instance = QobuzMusicService._internal();
  QobuzMusicService._internal();

  /// Default Eclipse Qobuz endpoint
  static const String defaultEndpoint =
      'https://qobuz-tidal-eclipse.cyrusna29.workers.dev/u/4opn823jmxs6yee60au24sse15kp';

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// Searches Qobuz tracks by query string using Eclipse /search endpoint
  Future<List<QobuzTrack>> searchTracks(String query, {String? endpoint}) async {
    if (query.trim().isEmpty) return [];
    final base = endpoint ?? defaultEndpoint;

    try {
      final url = Uri.parse(
        '$base/search?q=${Uri.encodeComponent(query.trim())}',
      );
      final res = await http
          .get(
            url,
            headers: {
              'User-Agent': userAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final tracksList = (data['tracks'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map((json) => QobuzTrack.fromJson(json))
                .where((t) => t.id.isNotEmpty)
                .toList() ??
            [];
        return tracksList;
      } else {
        appLogger.w('Qobuz search HTTP error ${res.statusCode} for "$query"');
      }
    } catch (e) {
      appLogger.e('Failed to search Qobuz tracks for "$query": $e');
    }
    return [];
  }

  /// Resolves direct audio stream URL from Qobuz Eclipse /stream/{id} endpoint
  Future<({String url, String format, String quality})?> getAudioStream(
    String trackId, {
    String? endpoint,
  }) async {
    final base = endpoint ?? defaultEndpoint;
    try {
      final url = Uri.parse('$base/stream/$trackId');
      final res = await http
          .get(
            url,
            headers: {
              'User-Agent': userAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final streamUrl = data['url']?.toString();
        if (streamUrl != null && streamUrl.isNotEmpty) {
          final format = data['format']?.toString() ?? 'flac';
          final quality = data['quality']?.toString() ?? 'FLAC Hi-Res';
          return (url: streamUrl, format: format, quality: quality);
        }
      } else {
        appLogger.w('Qobuz stream HTTP error ${res.statusCode} for track $trackId');
      }
    } catch (e) {
      appLogger.e('Failed to get Qobuz stream for track $trackId: $e');
    }
    return null;
  }

  /// Matches a DeezerTrack with Qobuz and returns the resolved FLAC stream URL & headers
  Future<({String url, Map<String, String> headers})?> resolveLosslessUrl(
    DeezerTrack track, {
    String? endpoint,
  }) async {
    try {
      final title = track.title;
      final artist = track.artist?.name ?? '';
      final query = '$title $artist'.trim();

      appLogger.i('Resolving FLAC lossless track on Qobuz for "$query"...');
      var results = await searchTracks(query, endpoint: endpoint);

      // Fallback search with cleaned title if no results found
      if (results.isEmpty) {
        final cleanTitle = _cleanTitle(title);
        if (cleanTitle != title) {
          final fallbackQuery = '$cleanTitle $artist'.trim();
          appLogger.i('Retrying Qobuz search with cleaned query "$fallbackQuery"...');
          results = await searchTracks(fallbackQuery, endpoint: endpoint);
        }
      }

      if (results.isEmpty) {
        appLogger.w('No Qobuz search results found for "$query"');
        return null;
      }

      final matchedTrack = _pickBestMatch(track, results);
      if (matchedTrack == null) return null;

      final streamResult = await getAudioStream(
        matchedTrack.id,
        endpoint: endpoint,
      );
      if (streamResult != null && streamResult.url.isNotEmpty) {
        appLogger.i(
          'Resolved Qobuz Lossless stream (${streamResult.quality}) for ${track.title} (ID: ${matchedTrack.id})',
        );
        return (
          url: streamResult.url,
          headers: <String, String>{
            'User-Agent': userAgent,
          },
        );
      }
    } catch (e) {
      appLogger.e('Qobuz resolution error for ${track.title}: $e');
    }
    return null;
  }

  String _cleanTitle(String raw) {
    return raw
        .replaceAll(RegExp(r'\(feat\.[^)]+\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(ft\.[^)]+\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[feat\.[^\]]+\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[ft\.[^\]]+\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(Radio Edit\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(Remastered[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[Remastered[^\]]*\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  QobuzTrack? _pickBestMatch(DeezerTrack track, List<QobuzTrack> candidates) {
    if (candidates.isEmpty) return null;

    final normTitle = _normalizeString(track.title);
    final normTitleShort = track.titleShort != null ? _normalizeString(track.titleShort!) : normTitle;
    final normArtist = _normalizeString(track.artist?.name ?? '');
    final trackDuration = track.duration ?? 0;

    QobuzTrack? bestTrack;
    var bestScore = -1;

    for (final c in candidates) {
      var score = 0;
      final cTitle = _normalizeString(c.title);
      final cArtist = _normalizeString(c.artist);

      // Title matching
      if (cTitle == normTitle || cTitle == normTitleShort) {
        score += 50;
      } else if (cTitle.contains(normTitle) || normTitle.contains(cTitle) ||
                 cTitle.contains(normTitleShort) || normTitleShort.contains(cTitle)) {
        score += 35;
      }

      // Artist matching
      if (normArtist.isNotEmpty) {
        if (cArtist == normArtist) {
          score += 40;
        } else if (cArtist.contains(normArtist) || normArtist.contains(cArtist)) {
          score += 25;
        }
      } else {
        score += 20;
      }

      // Duration matching (bonus for close length within 4 seconds)
      if (trackDuration > 0 && c.durationSeconds > 0) {
        final diff = (trackDuration - c.durationSeconds).abs();
        if (diff <= 2) {
          score += 20;
        } else if (diff <= 5) {
          score += 10;
        } else if (diff <= 10) {
          score += 5;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestTrack = c;
      }
    }

    return bestTrack ?? candidates.first;
  }

  String _normalizeString(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }
}
