import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lrc/lrc.dart';

import '../api/models/deezer_track.dart';

/// Pluggable lyrics backend.
abstract class LyricsService {
  Future<String?> getLyrics({
    required int trackId,
    required String title,
    required String artist,
    String? album,
    int? duration,
  });
}

class LrcLibLyricsService implements LyricsService {
  LrcLibLyricsService(this._dio);
  final Dio _dio;

  @override
  Future<String?> getLyrics({
    required int trackId,
    required String title,
    required String artist,
    String? album,
    int? duration,
  }) async {
    // 1. Try exact match first.
    final exact = await _get(title, artist, album, duration);
    if (exact != null) return exact;

    // 2. Try exact match without album & duration (since Deezer duration/album often differ).
    final exactRelaxed = await _get(title, artist, null, null);
    if (exactRelaxed != null) return exactRelaxed;

    // 3. Clean title and try exact match again.
    final cleanTitle = _clean(title);
    final cleanArtist = _clean(artist);
    if (cleanTitle != title || cleanArtist != artist) {
      final cleaned = await _get(cleanTitle, cleanArtist, null, null);
      if (cleaned != null) return cleaned;
    }

    // 3. Fallback to search if exact match fails.
    try {
      final res = await _dio.get<List<dynamic>>(
        'https://lrclib.net/api/search',
        queryParameters: {
          'q': '$cleanArtist $cleanTitle',
        },
      );
      if (res.statusCode == 200 && res.data != null && res.data!.isNotEmpty) {
        final best = res.data!.first as Map<String, dynamic>;
        return best['syncedLyrics'] as String? ?? best['plainLyrics'] as String?;
      }
    } catch (e) {
      debugPrint('lrclib search error: $e');
    }

    return null;
  }

  Future<String?> _get(String title, String artist, String? album, int? duration) async {
    try {
      final query = <String, dynamic>{
        'artist_name': artist,
        'track_name': title,
      };
      if (album != null) query['album_name'] = album;
      if (duration != null) query['duration'] = duration;

      final res = await _dio.get<Map<String, dynamic>>(
        'https://lrclib.net/api/get',
        queryParameters: query,
      );

      if (res.statusCode == 200 && res.data != null) {
        final data = res.data!;
        return data['syncedLyrics'] as String? ?? data['plainLyrics'] as String?;
      }
    } catch (e) {
      if (e is DioException && e.response?.statusCode != 404) {
        debugPrint('lrclib get error: $e');
      }
    }
    return null;
  }

  String _clean(String s) {
    return s
        .split(' - ')[0]
        .split(' (')[0]
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .trim();
  }
}

class CompositeLyricsService implements LyricsService {
  CompositeLyricsService(this._az, this._lrc);
  final LyricsService _az;
  final LyricsService _lrc;

  @override
  Future<String?> getLyrics({
    required int trackId,
    required String title,
    required String artist,
    String? album,
    int? duration,
  }) async {
    // Try AZLyrics first
    final az = await _az.getLyrics(
      trackId: trackId,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
    );
    if (az != null && az.trim().isNotEmpty) return az;

    // Fallback to LRCLIB
    return _lrc.getLyrics(
      trackId: trackId,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
    );
  }
}

class AzLyricsService implements LyricsService {
  AzLyricsService(this._dio);
  final Dio _dio;

  @override
  Future<String?> getLyrics({
    required int trackId,
    required String title,
    required String artist,
    String? album,
    int? duration,
  }) async {
    final cleanArtist = _formatForAz(artist, isArtist: true);
    final cleanTitle = _formatForAz(title, isArtist: false);
    if (cleanArtist.isEmpty || cleanTitle.isEmpty) return null;

    final url = 'https://www.azlyrics.com/lyrics/$cleanArtist/$cleanTitle.html';
    try {
      final res = await _dio.get<String>(url);
      if (res.statusCode == 200 && res.data != null) {
        return _parseAzHtml(res.data!);
      }
    } catch (e) {
      if (e is DioException && e.response?.statusCode != 404) {
        debugPrint('azlyrics get error: $e');
      }
    }
    return null;
  }

  String _formatForAz(String s, {required bool isArtist}) {
    var str = s.toLowerCase();
    // AZLyrics strips "The " from the beginning of artist names
    if (isArtist && str.startsWith('the ')) {
      str = str.substring(4);
    }
    // Remove featured artists from title
    if (!isArtist) {
      str = str.split('feat.')[0].split('ft.')[0].split('(')[0];
    }
    return str.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String? _parseAzHtml(String html) {
    const startMarker = '<!-- Usage of azlyrics.com content by any third-party lyrics provider is prohibited by our licensing agreement. Sorry about that. -->';
    final startIndex = html.indexOf(startMarker);
    if (startIndex == -1) return null;

    final afterStart = html.substring(startIndex + startMarker.length);
    final endIndex = afterStart.indexOf('</div>');
    if (endIndex == -1) return null;

    final rawLyrics = afterStart.substring(0, endIndex).trim();
    // Replace <br> and <br/> with \n
    final plainText = rawLyrics
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '') // Strip other HTML tags
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
        
    return plainText;
  }
}


final lyricsServiceProvider = Provider<LyricsService>((ref) {
  // Use a standard browser User-Agent for AZLyrics scraping
  final dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
      },
      followRedirects: true,
      maxRedirects: 3,
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      return client;
    },
  );
  return CompositeLyricsService(
    AzLyricsService(dio),
    LrcLibLyricsService(dio),
  );
});

/// One parsed lyric line.
class LyricLine {
  const LyricLine({required this.timestamp, required this.text});
  final Duration timestamp;
  final String text;
}

/// Parsed lyrics for a track. `lines` is empty when no lyrics found.
class TrackLyrics {
  const TrackLyrics({required this.trackId, required this.lines, this.synced = false});
  final int trackId;
  final List<LyricLine> lines;
  final bool synced;

  bool get isEmpty => lines.isEmpty;
}

/// Async lyric loader for a given track.
final lyricsForTrackProvider =
    FutureProvider.family<TrackLyrics, DeezerTrack>((ref, track) async {
  final svc = ref.watch(lyricsServiceProvider);
  final lyricTitle = _lyricsTitle(track);
  final lyricArtist = _lyricsArtist(track);
  final raw = await svc.getLyrics(
    trackId: track.id,
    title: lyricTitle,
    artist: lyricArtist,
    album: _lyricsAlbum(track),
    duration: track.duration,
  );
  if (raw == null || raw.trim().isEmpty) {
    return TrackLyrics(trackId: track.id, lines: const <LyricLine>[]);
  }
  // Try LRC first.
  if (Lrc.isValid(raw)) {
    try {
      final parsed = Lrc.parse(raw);
      final lines = parsed.lyrics
          .map(
            (l) => LyricLine(
              timestamp: l.timestamp,
              text: l.lyrics,
            ),
          )
          .toList(growable: false);
      return TrackLyrics(trackId: track.id, lines: lines, synced: true);
    } catch (_) {
      // fall through to plain-text path
    }
  }
  final plain = raw
      .split(RegExp(r'\r?\n'))
      .where((s) => s.trim().isNotEmpty)
      .map((s) => LyricLine(timestamp: Duration.zero, text: s))
      .toList(growable: false);
  return TrackLyrics(trackId: track.id, lines: plain);
});


bool _isYoutubeLyricsTrack(DeezerTrack track) =>
    track.link?.startsWith('wave://youtube') == true || track.id < 0;

String _lyricsTitle(DeezerTrack track) {
  final titleShort = track.titleShort?.trim();
  if (_isYoutubeLyricsTrack(track) && titleShort != null && titleShort.isNotEmpty) {
    return _cleanLyricsText(titleShort);
  }
  return _cleanLyricsText(track.title);
}

String _lyricsArtist(DeezerTrack track) {
  final artist = track.artist?.name.trim() ?? '';
  if (artist.isNotEmpty && artist.toLowerCase() != 'youtube') {
    return _cleanLyricsText(artist);
  }

  // Last resort for YouTube titles like "Artist - Song".
  if (_isYoutubeLyricsTrack(track)) {
    final raw = track.titleVersion?.trim() ?? track.title;
    final parts = raw.split(RegExp(r'\s+[-–—|]\s+'));
    if (parts.length >= 2 && parts.first.trim().isNotEmpty) {
      return _cleanLyricsText(parts.first.trim());
    }
  }
  return artist;
}

String? _lyricsAlbum(DeezerTrack track) {
  if (_isYoutubeLyricsTrack(track)) return null;
  return track.album?.title;
}

String _cleanLyricsText(String value) {
  return value
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .replaceAll(
        RegExp(
          r'\((official\s+)?(music\s+)?video\)|\((official\s+)?audio\)|\((official\s+)?lyrics?\)|\((lyric\s+video)\)|\(hd\)|\(4k\)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+', multiLine: true), ' ')
      .trim();
}
