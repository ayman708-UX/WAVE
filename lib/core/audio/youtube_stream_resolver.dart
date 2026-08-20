import 'dart:io' show Platform;

import 'package:hive/hive.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../services/youtube_audio_extractor.dart';
import '../api/models/deezer_track.dart';
import '../storage/hive_boxes.dart';
import '../utils/app_logger.dart';
import '../api/convertytmp3_client.dart';
import '../utils/youtube_stream_http.dart';
import 'youtube_rate_limit_guard.dart';

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

  // Low-request mode: only test a small number of video candidates/streams.
  // This reduces YouTube manifest requests per play/download.
  static const int _maxVideoCandidatesToResolve = 2;
  static const int _maxAudioStreamsToProbe = 2;

  final YoutubeExplode _yt = YoutubeExplode();
  YoutubeExplode get yt => _yt;

  final Map<int, VideoId> _cache = <int, VideoId>{};

  /// Returns a direct stream URL and User-Agent for [track], or `null` if no
  /// backend could resolve it.
  Future<({String url, String? userAgent})?> resolveUrl(
    DeezerTrack track, {
    bool verifyStream = true,
    bool allowExplodeFallback = true,
  }) async {
    YoutubeRateLimitGuard.throwIfLimited();

    // 1. If the user tapped a real YouTube listing, play that exact video
    final directVideoId = _youtubeVideoId(track);
    if (directVideoId != null) {
      final direct = await _resolveVideoIdForPlayback(
        track,
        VideoId(directVideoId),
        saveMatch: true,
        verifyStream: verifyStream,
        timeout: const Duration(seconds: 4),
      );
      if (direct != null) return direct;

      appLogger.w('Exact YouTube listing failed: $directVideoId');
      return null;
    }

    // 2. Fast direct extractor (1-to-1 NuvioTV InAppYouTubeExtractor port)
    final fast = await resolveFastUrlOnly(
      track,
      timeout: const Duration(seconds: 4),
      verifyStream: true,
    );
    if (fast != null) return fast;

    // 3. Convertytmp3 Stream Resolution Fallback
    VideoId? vidId = _cache[track.id];
    if (vidId == null) {
      final savedId = _cachedVideoIdFor(track.id);
      if (savedId != null) vidId = VideoId(savedId);
    }
    
    if (vidId == null) {
      try {
        final query = _buildQuery(track);
        final results = await YoutubeRateLimitGuard.runLowRequest(
          () => _yt.search.search(query).timeout(const Duration(seconds: 3)),
        );
        if (results.isNotEmpty) {
           vidId = results.first.id;
        }
      } catch (_) {}
    }

    if (vidId != null) {
      try {
        final streamUrl = await Convertytmp3Client.getStreamUrl(vidId.value);
        if (streamUrl != null) {
          appLogger.i('Resolved via Convertytmp3Client for ${track.title}');
          _cache[track.id] = vidId;
          await _saveVideoIdFor(track.id, vidId);
          return (
            url: streamUrl,
            userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
          );
        }
      } catch (e) {
        appLogger.w('Convertytmp3 resolution failed: $e');
      }
    }

    // 4. Conservative fallback: youtube_explode_dart (as last resort)
    if (allowExplodeFallback) {
      try {
        final info = await resolveStreamInfo(
          track,
        ).timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (info != null) {
          final url = info.url.toString();
          return (url: url, userAgent: YoutubeStreamHttp.userAgentForUrl(url));
        }
      } catch (e) {
        if (YoutubeRateLimitGuard.isRateLimitError(e)) _handleRateLimit(e);
        appLogger.w('youtube_explode_dart fallback failed: $e');
      }
    }

    appLogger.e('All stream resolution backends failed for ${track.title}');
    return null;
  }

  /// Fast/direct resolver used by playback and by the v23P download manager.
  /// It must be cheap: direct YouTube ID -> saved match -> one fast extractor
  /// search. It deliberately does not run youtube_explode fallback here.
  Future<({String url, String? userAgent})?> resolveFastUrlOnly(
    DeezerTrack track, {
    Duration timeout = const Duration(seconds: 4),
    bool verifyStream = false,
  }) async {
    YoutubeRateLimitGuard.throwIfLimited();

    final directVideoId = _youtubeVideoId(track);
    if (directVideoId != null) {
      final direct = await _resolveVideoIdForPlayback(
        track,
        VideoId(directVideoId),
        saveMatch: true,
        verifyStream: verifyStream,
        timeout: timeout,
      );
      if (direct != null) return direct;
      appLogger.w('Fast direct YouTube listing failed: $directVideoId');
      return null;
    }

    final cachedVid = _cache[track.id];
    if (cachedVid != null) {
      final cached = await _resolveVideoIdForPlayback(
        track,
        cachedVid,
        saveMatch: false,
        verifyStream: verifyStream,
        timeout: const Duration(seconds: 4),
      );
      if (cached != null) return cached;
      _cache.remove(track.id);
    }

    final savedVideoId = _cachedVideoIdFor(track.id);
    if (savedVideoId != null) {
      final saved = await _resolveVideoIdForPlayback(
        track,
        VideoId(savedVideoId),
        saveMatch: true,
        verifyStream: verifyStream,
        timeout: const Duration(seconds: 4),
      );
      if (saved != null) return saved;
      await _removeVideoIdFor(track.id);
    }

    try {
      final res = await YoutubeRateLimitGuard.runLowRequest(
        () => YoutubeAudioExtractor.instance
            .extract(
              _resolverTitle(track),
              _resolverArtist(track),
              targetDuration: track.duration != null
                  ? Duration(seconds: track.duration!)
                  : null,
              titleVersion: _resolverTitleVersion(track),
              verifyStream: verifyStream,
            )
            .timeout(timeout, onTimeout: () => null),
      );
      if (res != null) {
        final videoId = VideoId(res.videoId);
        _cache[track.id] = videoId;
        await _saveVideoIdFor(track.id, videoId);
        appLogger.i('Resolved audio URL via fast extractor for ${track.title}');
        return (url: res.audioUrl, userAgent: res.userAgent);
      }
    } catch (e) {
      if (YoutubeRateLimitGuard.isRateLimitError(e)) _handleRateLimit(e);
      appLogger.w('YoutubeAudioExtractor fast path failed: $e');
    }

    return null;
  }

  Future<({String url, String? userAgent})?> _resolveVideoIdForPlayback(
    DeezerTrack track,
    VideoId videoId, {
    required bool saveMatch,
    required bool verifyStream,
    required Duration timeout,
  }) async {
    // 1. Direct extractor (1-to-1 NuvioTV InAppYouTubeExtractor port)
    try {
      final res = await YoutubeRateLimitGuard.runLowRequest(
        () => YoutubeAudioExtractor.instance.getAudioUrl(
          videoId.value,
          verifyStream: true,
        ),
      ).timeout(timeout, onTimeout: () => null);
      if (res != null) {
        _cache[track.id] = videoId;
        if (saveMatch) await _saveVideoIdFor(track.id, videoId);
        return (url: res.url, userAgent: res.userAgent);
      }
    } catch (e) {
      if (YoutubeRateLimitGuard.isRateLimitError(e)) _handleRateLimit(e);
      appLogger.w('Fast video id playback resolve failed for $videoId: $e');
    }

    // 2. Convertytmp3 fallback
    try {
      final streamUrl = await Convertytmp3Client.getStreamUrl(videoId.value);
      if (streamUrl != null) {
        _cache[track.id] = videoId;
        if (saveMatch) await _saveVideoIdFor(track.id, videoId);
        appLogger.i('Resolved videoId $videoId via Convertytmp3Client');
        return (
          url: streamUrl,
          userAgent:
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
        );
      }
    } catch (e) {
      appLogger.w('Convertytmp3 direct videoId resolve failed for $videoId: $e');
    }

    return null;
  }

  List<YoutubeApiClient> _youtubeApiClients() {
    // Keep this list short. Passing many clients can make one manifest resolve
    // feel like several hidden attempts.
    return Platform.isAndroid
        ? <YoutubeApiClient>[
            YoutubeApiClient.android,
            YoutubeApiClient.androidSdkless,
            YoutubeApiClient.androidVr,
          ]
        : <YoutubeApiClient>[
            YoutubeApiClient.androidVr,
            YoutubeApiClient.ios,
            YoutubeApiClient.android,
          ];
  }

  Future<AudioOnlyStreamInfo?> resolveStreamInfo(DeezerTrack track) async {
    final query = _buildQuery(track);

    final clients = _youtubeApiClients();

    try {
      final directVideoId = _youtubeVideoId(track);
      if (directVideoId != null) {
        final directInfo = await _streamInfoForVideoId(
          VideoId(directVideoId),
          clients,
        );
        if (directInfo != null) {
          _cache[track.id] = VideoId(directVideoId);
          await _saveVideoIdFor(track.id, VideoId(directVideoId));
          return directInfo;
        }
        appLogger.w(
          'yt: direct YouTube listing had no playable audio: $directVideoId',
        );
      }

      final cachedVid = _cache[track.id];
      if (cachedVid != null) {
        final cachedInfo = await _streamInfoForVideoId(cachedVid, clients);
        if (cachedInfo != null) return cachedInfo;
        _cache.remove(track.id);
      }

      final savedVideoId = _cachedVideoIdFor(track.id);
      if (savedVideoId != null) {
        final savedInfo = await _streamInfoForVideoId(
          VideoId(savedVideoId),
          clients,
        );
        if (savedInfo != null) {
          _cache[track.id] = VideoId(savedVideoId);
          return savedInfo;
        }
        await _removeVideoIdFor(track.id);
      }

      final results = await YoutubeRateLimitGuard.runLowRequest(
        () => _yt.search.search(query),
      );
      if (results.isEmpty) {
        appLogger.w('yt: no results for "$query"');
        return null;
      }

      final candidates = <Video>[];
      for (final v in results.take(5)) {
        if (v.isLive) continue;
        final dur = v.duration;
        if (dur != null && dur.inSeconds < 30) continue;
        candidates.add(v);
      }

      final title = _resolverTitle(track);
      final artist = _resolverArtist(track);
      final titleVersion = _resolverTitleVersion(track) ?? '';
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

      final scored = <({Video video, double score})>[];
      for (final candidate in candidates) {
        final candDuration = candidate.duration;
        final normCandTitle = candidate.title
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim();

        double score = 0.0;

        if (normSongTitle.isNotEmpty && normCandTitle.contains(normSongTitle)) {
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

        if (normVersion.isNotEmpty && normCandTitle.contains(normVersion)) {
          score += 40.0;
        }

        if (normArtist.isNotEmpty && normCandTitle.contains(normArtist)) {
          score += 30.0;
        }

        final candIsLive = normCandTitle.contains('live');
        score += candIsLive == targetIsLive ? 20.0 : -50.0;

        final candIsRemix = normCandTitle.contains('remix');
        score += candIsRemix == targetIsRemix ? 20.0 : -50.0;

        final candIsCover = normCandTitle.contains('cover');
        score += candIsCover == targetIsCover ? 20.0 : -50.0;

        final candIsAcoustic = normCandTitle.contains('acoustic');
        score += candIsAcoustic == targetIsAcoustic ? 20.0 : -50.0;

        if (targetDuration != null && candDuration != null) {
          final diffSecs = (candDuration.inSeconds - targetDuration.inSeconds)
              .abs();
          if (diffSecs <= 4) {
            score += 150.0;
          } else if (diffSecs <= 10) {
            score += 50.0;
          } else if (diffSecs <= 20) {
            score += 10.0;
          } else if (diffSecs <= 40) {
            score -= diffSecs * 3.0;
          } else {
            score -= 500.0 + diffSecs * 5.0;
          }
        }

        scored.add((video: candidate, score: score));
      }

      scored.sort((a, b) => b.score.compareTo(a.score));
      final ranked = <Video>[
        ...scored.map((candidate) => candidate.video),
        ...candidates,
        results.first,
      ];

      final triedVideoIds = <VideoId>{};
      for (final video in ranked) {
        if (!triedVideoIds.add(video.id)) continue;
        if (triedVideoIds.length > _maxVideoCandidatesToResolve) break;

        final info = await _streamInfoForVideoId(video.id, clients);
        if (info != null) {
          _cache[track.id] = video.id;
          await _saveVideoIdFor(track.id, video.id);
          return info;
        }
        appLogger.w('yt: candidate ${video.id} had no playable audio');
      }

      return null;
    } catch (e) {
      if (YoutubeRateLimitGuard.isRateLimitError(e)) _handleRateLimit(e);
      appLogger.e('yt resolveStreamInfo failed for "$query": $e');
      // Clear cache so we don't permanently break this song.
      _cache.remove(track.id);
      await _removeVideoIdFor(track.id);
      return null;
    }
  }

  String? _cachedVideoIdFor(int trackId) {
    if (!Hive.isBoxOpen(HiveBoxes.youtubeMatches)) return null;
    final value = Hive.box<dynamic>(
      HiveBoxes.youtubeMatches,
    ).get(trackId.toString());
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  Future<void> _saveVideoIdFor(int trackId, VideoId videoId) async {
    if (!Hive.isBoxOpen(HiveBoxes.youtubeMatches)) return;
    await Hive.box<dynamic>(
      HiveBoxes.youtubeMatches,
    ).put(trackId.toString(), videoId.value);
  }

  Future<void> _removeVideoIdFor(int trackId) async {
    if (!Hive.isBoxOpen(HiveBoxes.youtubeMatches)) return;
    await Hive.box<dynamic>(
      HiveBoxes.youtubeMatches,
    ).delete(trackId.toString());
  }

  String _buildQuery(DeezerTrack track) {
    final artist = _resolverArtist(track);
    final version = _resolverTitleVersion(track) ?? '';
    final title = _resolverTitle(track);
    final queryTitle = version.isNotEmpty ? '$title $version' : title;

    final isLive = queryTitle.toLowerCase().contains('live');
    final suffix = isLive ? 'live' : 'official audio';

    return '$queryTitle $artist $suffix'.trim();
  }

  bool _isYoutubeTrack(DeezerTrack track) =>
      track.link?.startsWith('wave://youtube') == true || track.id < 0;

  String? _youtubeVideoId(DeezerTrack track) {
    final link = track.link;
    if (link == null) return null;
    const prefix = 'wave://youtube-video/';
    if (!link.startsWith(prefix)) return null;
    final id = link.substring(prefix.length).trim();
    return id.isEmpty ? null : id;
  }

  String _resolverTitle(DeezerTrack track) {
    if (_isYoutubeTrack(track)) {
      final raw = track.titleShort?.trim();
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return track.title.trim();
  }

  String _resolverArtist(DeezerTrack track) {
    final artist = track.artist?.name.trim() ?? '';
    if (artist.isNotEmpty) return artist;
    return _isYoutubeTrack(track) ? '' : artist;
  }

  String? _resolverTitleVersion(DeezerTrack track) {
    if (_isYoutubeTrack(track)) return null;
    final version = track.titleVersion?.trim();
    return version == null || version.isEmpty ? null : version;
  }

  Future<AudioOnlyStreamInfo?> _pickPlayableAudioOnly(
    List<AudioOnlyStreamInfo> streams,
  ) async {
    streams.sort((a, b) => b.bitrate.compareTo(a.bitrate));

    // Do not probe stream URLs here. The probe is an extra network hit and is
    // one of the reasons Play/Download sits on "finding playable audio".
    // The player/downloader will fail over if the chosen stream is actually bad.
    for (final stream in streams.take(_maxAudioStreamsToProbe)) {
      final url = stream.url.toString();
      if (_isExpiredSoon(url)) {
        appLogger.w('yt: skipped expired stream URL for itag ${stream.tag}');
        continue;
      }
      return stream;
    }

    return null;
  }

  Future<AudioOnlyStreamInfo?> _streamInfoForVideoId(
    VideoId videoId,
    List<YoutubeApiClient> clients,
  ) async {
    try {
      final manifest = await YoutubeRateLimitGuard.runLowRequest(
        () => _yt.videos.streamsClient.getManifest(videoId, ytClients: clients),
      );
      return _pickPlayableAudioOnly(manifest.audioOnly.toList());
    } catch (e) {
      if (YoutubeRateLimitGuard.isRateLimitError(e)) _handleRateLimit(e);
      appLogger.w('yt: manifest failed for $videoId: $e');
      return null;
    }
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

  Never _handleRateLimit(Object error) {
    YoutubeRateLimitGuard.record(error);
    appLogger.e('YouTube rate limit detected: $error');
    throw YoutubeRateLimitException(YoutubeRateLimitGuard.userMessage);
  }

  void dispose() {
    _yt.close();
    _cache.clear();
  }
}
