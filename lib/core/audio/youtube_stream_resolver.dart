import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../services/youtube_audio_extractor.dart';
import '../api/models/deezer_track.dart';
import '../utils/app_logger.dart';
import '../utils/youtube_stream_http.dart';

/// Resolves a [DeezerTrack] to a directly-playable audio stream URL.
///
/// The resolver tries multiple independent backends in order:
///
/// 1. Custom InnerTube extractor (fast, direct YouTube API).
/// 2. `youtube_explode_dart` (mature Dart library with multiple clients).
/// 3. Public Invidious / Piped instances (proxy services, often work when
///    direct YouTube extraction is blocked by network/region).
///
/// Results are cached in-memory for the lifetime of the app to avoid hitting
/// the network on every replay.
class YoutubeStreamResolver {
  YoutubeStreamResolver();

  final YoutubeExplode _yt = YoutubeExplode();
  YoutubeExplode get yt => _yt;

  final Map<int, VideoId> _cache = <int, VideoId>{};

  /// Returns a direct stream URL and User-Agent for [track], or `null` if no
  /// backend could resolve it.
  Future<({String url, String? userAgent})?> resolveUrl(
    DeezerTrack track,
  ) async {
    // 1. Primary fast path: custom InnerTube extractor.
    try {
      final videoId = await YoutubeAudioExtractor.instance.searchVideoId(
        track.title,
        track.artist?.name ?? '',
        targetDuration: track.duration != null
            ? Duration(seconds: track.duration!)
            : null,
        titleVersion: track.titleVersion,
      );
      if (videoId != null) {
        final res = await YoutubeAudioExtractor.instance.getAudioUrl(videoId);
        if (res != null) {
          appLogger.i(
            'Resolved audio URL via fast extractor for ${track.title}',
          );
          return (url: res.url, userAgent: res.userAgent);
        }
      }
    } catch (e) {
      appLogger.w('YoutubeAudioExtractor failed: $e');
    }

    // 2. Fallback path: youtube_explode_dart.
    try {
      final info = await resolveStreamInfo(track);
      if (info != null) {
        final url = info.url.toString();
        return (url: url, userAgent: YoutubeStreamHttp.userAgentForUrl(url));
      }
    } catch (e) {
      appLogger.w('youtube_explode_dart fallback failed: $e');
    }

    appLogger.e('All stream resolution backends failed for ${track.title}');
    return null;
  }

  Future<AudioOnlyStreamInfo?> resolveStreamInfo(DeezerTrack track) async {
    final query = _buildQuery(track);

    // Fallback list of clients in priority order.
    final clients = <YoutubeApiClient>[
      YoutubeApiClient.androidVr,
      YoutubeApiClient.ios,
      YoutubeApiClient.tv,
      YoutubeApiClient.androidSdkless,
      YoutubeApiClient.safari,
      YoutubeApiClient.mweb,
      YoutubeApiClient.android,
    ];

    try {
      VideoId? vid = _cache[track.id];

      if (vid == null) {
        final results = await _yt.search.search(query);
        if (results.isEmpty) {
          appLogger.w('yt: no results for "$query"');
          return null;
        }

        final candidates = <Video>[];
        for (final v in results.take(10)) {
          if (v.isLive) continue;
          final dur = v.duration;
          if (dur != null && dur.inSeconds < 30) continue;
          candidates.add(v);
        }

        Video? pick;
        if (candidates.isEmpty) {
          pick = results.first;
        } else {
          final title = track.title;
          final artist = track.artist?.name ?? '';
          final titleVersion = track.titleVersion ?? '';
          final targetDuration = track.duration != null
              ? Duration(seconds: track.duration!)
              : null;

          final normSongTitle = title
              .toLowerCase()
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .trim();
          final normArtist = artist
              .toLowerCase()
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .trim();
          final normVersion = titleVersion
              .toLowerCase()
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .trim();

          final targetIsLive =
              normSongTitle.contains('live') || normVersion.contains('live');
          final targetIsRemix =
              normSongTitle.contains('remix') || normVersion.contains('remix');
          final targetIsCover =
              normSongTitle.contains('cover') || normVersion.contains('cover');
          final targetIsAcoustic =
              normSongTitle.contains('acoustic') ||
              normVersion.contains('acoustic');

          double bestScore = -999999.0;

          for (final candidate in candidates) {
            final candDuration = candidate.duration;
            final normCandTitle = candidate.title
                .toLowerCase()
                .replaceAll(RegExp(r'[^\w\s]'), '')
                .trim();

            double score = 0.0;

            // 1. Title match score
            if (normSongTitle.isNotEmpty &&
                normCandTitle.contains(normSongTitle)) {
              score += 100.0;
            } else {
              final songWords = normSongTitle
                  .split(RegExp(r'\s+'))
                  .where((w) => w.length > 2)
                  .toList();
              if (songWords.isNotEmpty) {
                int matchingWords = 0;
                for (final word in songWords) {
                  if (normCandTitle.contains(word)) {
                    matchingWords++;
                  }
                }
                score += (matchingWords / songWords.length) * 60.0;
              }
            }

            if (normVersion.isNotEmpty) {
              if (normCandTitle.contains(normVersion)) {
                score += 40.0;
              }
            }

            // 2. Artist match score
            if (normArtist.isNotEmpty && normCandTitle.contains(normArtist)) {
              score += 30.0;
            }

            // 3. Live performance match
            final candIsLive = normCandTitle.contains('live');
            if (candIsLive == targetIsLive) {
              score += 20.0;
            } else {
              score -= 50.0;
            }

            // 4. Remix match
            final candIsRemix = normCandTitle.contains('remix');
            if (candIsRemix == targetIsRemix) {
              score += 20.0;
            } else {
              score -= 50.0;
            }

            // 5. Cover match
            final candIsCover = normCandTitle.contains('cover');
            if (candIsCover == targetIsCover) {
              score += 20.0;
            } else {
              score -= 50.0;
            }

            // 6. Acoustic match
            final candIsAcoustic = normCandTitle.contains('acoustic');
            if (candIsAcoustic == targetIsAcoustic) {
              score += 20.0;
            } else {
              score -= 50.0;
            }

            // 7. Duration difference penalty
            if (targetDuration != null && candDuration != null) {
              final diffSecs =
                  (candDuration.inSeconds - targetDuration.inSeconds).abs();
              if (diffSecs <= 4) {
                score += 150.0;
              } else if (diffSecs <= 10) {
                score += 50.0;
              } else if (diffSecs <= 20) {
                score += 10.0;
              } else if (diffSecs <= 40) {
                score -= (diffSecs * 3.0);
              } else {
                score -= 500.0 + (diffSecs * 5.0);
              }
            }

            if (score > bestScore) {
              bestScore = score;
              pick = candidate;
            }
          }
        }
        pick ??= results.first;
        vid = pick.id;
        _cache[track.id] = vid;
      }

      final manifest = await _yt.videos.streamsClient.getManifest(
        vid,
        ytClients: clients,
      );
      return _pickPlayableAudioOnly(manifest.audioOnly.toList());
    } catch (e) {
      appLogger.e('yt resolveStreamInfo failed for "$query": $e');
      // Clear cache so we don't permanently break this song.
      _cache.remove(track.id);
      return null;
    }
  }

  String _buildQuery(DeezerTrack track) {
    final artist = track.artist?.name ?? '';
    final version = track.titleVersion ?? '';
    final title = track.title;
    final queryTitle = version.isNotEmpty ? '$title $version' : title;

    final isLive = queryTitle.toLowerCase().contains('live');
    final suffix = isLive ? 'live' : 'audio';

    return '$queryTitle $artist $suffix'.trim();
  }

  Future<AudioOnlyStreamInfo?> _pickPlayableAudioOnly(
    List<AudioOnlyStreamInfo> streams,
  ) async {
    streams.sort((a, b) => b.bitrate.compareTo(a.bitrate));

    for (final stream in streams) {
      final url = stream.url.toString();
      if (_isExpiredSoon(url)) {
        appLogger.w('yt: skipped expired stream URL for itag ${stream.tag}');
        continue;
      }

      final playable = await YoutubeStreamHttp.probe(
        url,
        userAgent: YoutubeStreamHttp.userAgentForUrl(url),
      );
      if (playable) return stream;

      appLogger.w('yt: stream probe rejected itag ${stream.tag}');
    }

    return null;
  }

  bool _isExpiredSoon(String url) {
    try {
      final expire = Uri.parse(url).queryParameters['expire'];
      final secs = int.tryParse(expire ?? '');
      if (secs == null) return false;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
      return DateTime.now().isAfter(
        expiresAt.subtract(const Duration(minutes: 2)),
      );
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _yt.close();
    _cache.clear();
  }
}
