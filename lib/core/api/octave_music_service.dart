import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/deezer_track.dart';
import '../utils/app_logger.dart';

class OctaveTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;

  OctaveTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
  });

  factory OctaveTrack.fromJson(Map<String, dynamic> json) {
    final albumData = json['album'] is Map<String, dynamic>
        ? json['album'] as Map<String, dynamic>
        : {};
    final artistData = json['artist'] is Map<String, dynamic>
        ? json['artist'] as Map<String, dynamic>
        : {};

    return OctaveTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Track',
      artist: artistData['name']?.toString() ??
          json['artist']?.toString() ??
          'Unknown Artist',
      album: albumData['title']?.toString() ??
          json['album']?.toString() ??
          'Single',
      durationSeconds: int.tryParse(
            json['duration']?.toString() ??
                json['durationSeconds']?.toString() ??
                '',
          ) ??
          0,
    );
  }
}

class OctaveMusicService {
  static final OctaveMusicService instance = OctaveMusicService._internal();
  OctaveMusicService._internal();

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  String? _cachedToken;
  DateTime? _tokenExpiry;

  /// Fetches a valid playback token from Octave Streaming API
  Future<String?> getPlaybackToken() async {
    if (_cachedToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _cachedToken;
    }

    try {
      final res = await http
          .get(
            Uri.parse('https://api.octavestreaming.com/api/playback-token'),
            headers: {
              'User-Agent': userAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final token = data['token']?.toString();
        final expiresIn =
            int.tryParse(data['expiresIn']?.toString() ?? '') ?? 43200;

        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
          _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
          return token;
        }
      }
    } catch (e) {
      appLogger.e('Failed to get Octave playback token: $e');
    }
    return null;
  }

  /// Searches Octave tracks by query string
  Future<List<OctaveTrack>> searchTracks(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final url = Uri.parse(
        'https://music.octavestreaming.com/api/search?q=${Uri.encodeComponent(query)}',
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
                .map((json) => OctaveTrack.fromJson(json))
                .where((t) => t.id.isNotEmpty)
                .toList() ??
            [];
        return tracksList;
      }
    } catch (e) {
      appLogger.e('Failed to search Octave tracks: $e');
    }
    return [];
  }

  /// Resolves direct audio stream URL from Octave
  Future<String?> getAudioStreamUrl(
    String trackId, {
    String quality = 'lossless',
  }) async {
    final token = await getPlaybackToken();
    if (token == null || token.isEmpty) return null;
    return 'https://api.octavestreaming.com/audio/$quality?track=$trackId&token=$token';
  }

  /// Matches a DeezerTrack with Octave search engine and returns the resolved FLAC stream URL & HTTP headers
  Future<({String url, Map<String, String> headers})?> resolveLosslessUrl(
    DeezerTrack track,
  ) async {
    try {
      final title = track.title;
      final artist = track.artist?.name ?? '';
      final query = '$title $artist'.trim();

      appLogger.i('Resolving lossless track on Octave for "$query"...');
      final results = await searchTracks(query);

      if (results.isEmpty) {
        appLogger.w('No Octave search results found for "$query"');
        return null;
      }

      final matchedTrack = _pickBestMatch(track, results);
      if (matchedTrack == null) return null;

      final streamUrl = await getAudioStreamUrl(
        matchedTrack.id,
        quality: 'lossless',
      );
      if (streamUrl != null && streamUrl.isNotEmpty) {
        appLogger.i(
          'Resolved Octave Lossless stream for ${track.title} (ID: ${matchedTrack.id})',
        );
        return (
          url: streamUrl,
          headers: <String, String>{
            'User-Agent': userAgent,
            'Referer': 'https://music.octavestreaming.com/',
          },
        );
      }
    } catch (e) {
      appLogger.e('Octave resolution error for ${track.title}: $e');
    }
    return null;
  }

  OctaveTrack? _pickBestMatch(DeezerTrack track, List<OctaveTrack> candidates) {
    if (candidates.isEmpty) return null;
    final normTitle = track.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
    final normArtist = (track.artist?.name ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();

    for (final c in candidates) {
      final cTitle = c.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim();
      final cArtist = c.artist
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim();

      if (cTitle.contains(normTitle) || normTitle.contains(cTitle)) {
        if (normArtist.isEmpty ||
            cArtist.contains(normArtist) ||
            normArtist.contains(cArtist)) {
          return c;
        }
      }
    }
    return candidates.first;
  }
}
