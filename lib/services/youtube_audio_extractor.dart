import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/utils/youtube_stream_http.dart';

/// Robust YouTube audio stream resolver.
///
/// Uses the InnerTube API directly (no HTML scraping) and cycles through a
/// variety of clients that are known to return plain (non-ciphered) audio URLs
/// for different networks/regions. Falls back gracefully when a video is
/// age-restricted, geo-blocked, or when a client is rejected.
///
/// The extractor is intentionally self-contained and does not require a JS
/// engine. Streams that require signature deciphering are skipped in favour of
/// clients that already provide signed URLs.
class YoutubeAudioExtractor {
  YoutubeAudioExtractor._();
  static final YoutubeAudioExtractor instance = YoutubeAudioExtractor._();

  static const String _tag = 'YoutubeAudioExtractor';

  /// Fallback InnerTube API key. Extracted keys are preferred but this works
  /// when the watch page cannot be fetched.
  static const String _fallbackApiKey =
      'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  static const Duration _configTtl = Duration(hours: 3);
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const int _maxVideoCandidates = 2;

  static const String _desktopUserAgent = YoutubeStreamHttp.desktopUserAgent;

  // Search client context. WEB is the most reliable for InnerTube search.
  static final _YtClient _searchClient = _YtClient(
    key: 'web_search',
    id: '1',
    version: '2.20250217.03.00',
    userAgent: _desktopUserAgent,
    context: {
      'clientName': 'WEB',
      'clientVersion': '2.20250217.03.00',
      'hl': 'en',
      'gl': 'US',
      'platform': 'DESKTOP',
    },
  );

  static final List<_YtClient> _clients = [
    // iOS 20.10.4 client - returns plain audio URLs without signature cipher.
    _YtClient(
      key: 'ios',
      id: '5',
      version: '20.10.4',
      userAgent:
          'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_1 like Mac OS X;)',
      context: {
        'clientName': 'IOS',
        'clientVersion': '20.10.4',
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'userAgent':
            'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_1 like Mac OS X;)',
        'platform': 'MOBILE',
        'osName': 'IOS',
        'osVersion': '18.1.0.22B83',
        'hl': 'en',
        'gl': 'US',
      },
    ),
    // Android 20.10.38 sdkless client.
    _YtClient(
      key: 'android',
      id: '3',
      version: '20.10.38',
      userAgent:
          'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
      context: {
        'clientName': 'ANDROID',
        'clientVersion': '20.10.38',
        'userAgent':
            'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
        'platform': 'MOBILE',
        'osName': 'Android',
        'osVersion': '11',
        'hl': 'en',
        'gl': 'US',
      },
    ),
    // Mobile web fallback.
    _YtClient(
      key: 'mweb',
      id: '2',
      version: '2.20260817.01.00',
      userAgent:
          'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/133.0.0.0 Mobile Safari/537.36',
      context: {
        'clientName': 'MWEB',
        'clientVersion': '2.20260817.01.00',
        'hl': 'en',
        'gl': 'US',
        'platform': 'MOBILE',
      },
      requiresVisitorData: true,
    ),
  ];

  // --- State ---
  _CachedConfig? _config;
  Future<_CachedConfig>? _configInFlight;

  final Map<String, _CachedVideoIds> _videoIdCache = {};
  final Map<String, _CachedStream> _streamCache = {};

  _YtClient? _lastSuccessfulClient;

  // ===========================================================================
  // Public API
  // ===========================================================================

  /// Search YouTube for [query] and return the best ranked videoId.
  ///
  /// Uses the InnerTube search API rather than scraping HTML, which is more
  /// stable across regions and less likely to be blocked.
  Future<String?> searchVideoId(
    String title,
    String artist, {
    Duration? targetDuration,
    String? titleVersion,
  }) async {
    final ids = await searchVideoIds(
      title,
      artist,
      targetDuration: targetDuration,
      titleVersion: titleVersion,
    );
    return ids.isEmpty ? null : ids.first;
  }

  /// Search YouTube and return ranked candidate videoIds.
  ///
  /// A single top result is not enough for reliable playback: some official
  /// videos are age/region restricted, livestreams, or only expose ciphered
  /// formats. The caller can try candidates in order until one yields a
  /// playable audio URL.
  Future<List<String>> searchVideoIds(
    String title,
    String artist, {
    Duration? targetDuration,
    String? titleVersion,
  }) async {
    final queryTitle = (titleVersion != null && titleVersion.isNotEmpty)
        ? '$title $titleVersion'
        : title;

    final queryLower = queryTitle.toLowerCase();
    final normVersionLower = titleVersion?.toLowerCase() ?? '';
    final String suffix;
    if (queryLower.contains('live') || normVersionLower.contains('live')) {
      suffix = 'live';
    } else if (queryLower.contains('remix') ||
        normVersionLower.contains('remix')) {
      suffix = 'remix';
    } else if (queryLower.contains('acoustic')) {
      suffix = 'acoustic';
    } else {
      suffix =
          'official audio'; // keeps remixes/covers lower in results by default
    }

    final searchQuery = '$queryTitle $artist $suffix'.trim();
    final cacheKey = targetDuration != null
        ? '$searchQuery|${targetDuration.inSeconds}'
        : searchQuery;

    final cached = _videoIdCache[cacheKey];
    if (cached != null && !cached.isExpired) return cached.videoIds;

    final config = await _ensureConfig();
    try {
      final ids = await _searchInnerTubeCandidates(
        config,
        searchQuery,
        title: title,
        artist: artist,
        targetDuration: targetDuration,
        titleVersion: titleVersion,
      );
      if (ids.isNotEmpty) {
        _videoIdCache[cacheKey] = _CachedVideoIds(ids);
      }
      return ids;
    } catch (e) {
      _log('searchVideoIds failed: $e');
      // Try a fresh config once.
      if (!_isForced(config)) {
        _config = null;
        try {
          final fresh = await _ensureConfig(forceRefresh: true);
          final ids = await _searchInnerTubeCandidates(
            fresh,
            searchQuery,
            title: title,
            artist: artist,
            targetDuration: targetDuration,
            titleVersion: titleVersion,
          );
          if (ids.isNotEmpty) {
            _videoIdCache[cacheKey] = _CachedVideoIds(ids);
          }
          return ids;
        } catch (e2) {
          _log('search retry failed: $e2');
        }
      }
      return const <String>[];
    }
  }

  /// Resolve a plaintext audio URL for [videoId].
  ///
  /// Returns the highest-bitrate adaptive audio stream, falling back to a
  /// progressive muxed stream if necessary. Only streams with a usable URL
  /// (not a cipher requiring JS execution) are returned.
  Future<({String url, String userAgent})?> getAudioUrl(
    String videoId, {
    bool verifyStream = true,
  }) async {
    final cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) {
      return (url: cached.url, userAgent: cached.userAgent);
    }

    final config = await _ensureConfig();
    return await _tryClients(
      config,
      videoId,
      verifyStream: verifyStream,
    );
  }

  Future<({String videoId, String audioUrl, String userAgent})?> extract(
    String title,
    String artist, {
    Duration? targetDuration,
    String? titleVersion,
    bool verifyStream = true,
  }) async {
    final ids = await searchVideoIds(
      title,
      artist,
      targetDuration: targetDuration,
      titleVersion: titleVersion,
    );
    for (final id in ids.take(1)) {
      try {
        final res = await getAudioUrl(id, verifyStream: verifyStream).timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            _log('candidate $id timed out');
            return null;
          },
        );
        if (res != null) {
          return (videoId: id, audioUrl: res.url, userAgent: res.userAgent);
        }
      } catch (e) {
        _log('candidate $id failed: $e');
      }
    }
    return null;
  }

  // ===========================================================================
  // Internals
  // ===========================================================================

  Future<_CachedConfig> _ensureConfig({bool forceRefresh = false}) {
    final existing = _config;
    if (!forceRefresh && existing != null && !existing.isExpired) {
      return Future.value(existing);
    }
    final inflight = _configInFlight;
    if (inflight != null) return inflight;
    final future = _fetchConfig(forceRefresh).whenComplete(() {
      _configInFlight = null;
    });
    _configInFlight = future;
    return future;
  }

  Future<_CachedConfig> _fetchConfig(bool forced) async {
    String? apiKey;
    String? visitorData;

    try {
      final resp = await http
          .get(
            Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ&hl=en'),
            headers: {
              'User-Agent': _desktopUserAgent,
              'Accept-Language': 'en-US,en;q=0.9',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },
          )
          .timeout(_requestTimeout);

      if (resp.statusCode == 200) {
        final body = resp.body;
        apiKey = _extractQuoted(body, 'INNERTUBE_API_KEY');
        visitorData = _extractQuoted(body, 'VISITOR_DATA');
      } else {
        _log('watch page HTTP ${resp.statusCode}');
      }
    } catch (e) {
      _log('watch page fetch failed: $e');
    }

    final c = _CachedConfig(
      apiKey: apiKey ?? _fallbackApiKey,
      visitorData: visitorData,
      forced: forced,
    );
    _config = c;
    return c;
  }

  String? _extractQuoted(String body, String key) {
    final idx = body.indexOf('"$key":"');
    if (idx == -1) return null;
    final start = idx + key.length + 4; // skip "key":"
    final end = body.indexOf('"', start);
    if (end == -1) return null;
    return body.substring(start, end).replaceAll(r'\u0026', '&');
  }

  Future<List<String>> _searchInnerTubeCandidates(
    _CachedConfig config,
    String query, {
    required String title,
    required String artist,
    Duration? targetDuration,
    String? titleVersion,
  }) async {
    final uri = Uri.parse(
      'https://www.youtube.com/youtubei/v1/search?key=${Uri.encodeQueryComponent(config.apiKey)}',
    );

    final headers = _commonHeaders(config, _searchClient);

    final body = jsonEncode({
      'query': query,
      'params': 'EgWKAQIIAWoKEAMQBBAJEAoQBQ==',
      'context': {'client': _searchClient.context},
    });

    final resp = await http
        .post(uri, headers: headers, body: body)
        .timeout(_requestTimeout);

    if (resp.statusCode != 200) {
      throw StateError('search API failed (${resp.statusCode})');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = _flattenSearchResults(data);

    final candidates = <_VideoCandidate>[];

    for (final renderer in results.take(10)) {
      final videoId = _str(renderer, 'videoId');
      if (videoId == null || videoId.length != 11) continue;

      // Skip live streams and very short clips.
      final isLive = (() {
        final badges = renderer['badges'];
        if (badges is List && badges.isNotEmpty) {
          final label = badges.first.toString().toLowerCase();
          if (label.contains('live')) return true;
        }
        return false;
      })();

      final lengthText = _extractLengthText(renderer);
      final duration = _parseDuration(lengthText);
      final videoTitle = _extractTitleText(renderer) ?? '';

      candidates.add(
        _VideoCandidate(
          id: videoId,
          title: videoTitle,
          duration: duration,
          isLive: isLive,
        ),
      );
    }

    if (candidates.isEmpty) return const <String>[];

    final normSongTitle = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
    final normArtist = artist
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
    final normVersion =
        titleVersion?.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim() ??
        '';

    final targetVariants = _detectVariants('$normSongTitle $normVersion');

    final scored = <({String id, double score})>[];

    for (final candidate in candidates) {
      if (candidate.isLive) continue;
      final candDuration = candidate.duration;
      if (candDuration != null && candDuration.inSeconds < 30) continue;

      final normCandTitle = candidate.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .trim();

      double score = 0.0;

      // 1. Title match score
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

      if (normVersion.isNotEmpty) {
        if (normCandTitle.contains(normVersion)) {
          score += 40.0;
        }
      }

      // 2. Artist match score
      if (normArtist.isNotEmpty && normCandTitle.contains(normArtist)) {
        score += 30.0;
      }

      // 3–6 + 8D: Unified variant / modifier matching
      final candVariants = _detectVariants(normCandTitle);
      final allVariants = <String>{...targetVariants, ...candVariants};
      for (final tag in allVariants) {
        if (targetVariants.contains(tag) == candVariants.contains(tag)) {
          score += 15.0; // Both sides agree → small bonus
        } else {
          score -=
              _variantPenalties[tag] ??
              350.0; // Weighted by how jarring the mismatch is
        }
      }

      // 7. Duration match (tiebreaker, never a trump card)
      if (targetDuration != null && candDuration != null) {
        final diffSecs = (candDuration.inSeconds - targetDuration.inSeconds)
            .abs();
        if (diffSecs <= 4) {
          score += 80.0; // ↓ from 150 — duration is a hint, not a trump
        } else if (diffSecs <= 10) {
          score += 25.0;
        } else if (diffSecs <= 20) {
          score += 5.0;
        } else if (diffSecs <= 40) {
          score -= diffSecs * 2.0;
        } else {
          score -= diffSecs * 5.0; // Proportional only — no flat -500 cliff
        }
      }

      scored.add((id: candidate.id, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final ranked = <String>[
      ...scored.map((candidate) => candidate.id),
      ...candidates.map((candidate) => candidate.id),
    ];
    return ranked.toSet().take(_maxVideoCandidates).toList(growable: false);
  }

  List<Map<String, dynamic>> _flattenSearchResults(Map<String, dynamic> data) {
    final out = <Map<String, dynamic>>[];
    final contents = _dig(data, [
      'contents',
      'twoColumnSearchResultsRenderer',
      'primaryContents',
      'sectionListRenderer',
      'contents',
    ]);
    if (contents is! List) return out;

    for (final section in contents) {
      final items = _dig(section, ['itemSectionRenderer', 'contents']);
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        final renderer = item['videoRenderer'] ?? item['compactVideoRenderer'];
        if (renderer is Map) {
          out.add(Map<String, dynamic>.from(renderer));
        }
      }
    }
    return out;
  }

  String? _extractLengthText(Map<String, dynamic> renderer) {
    final length = renderer['lengthText'];
    if (length is Map) {
      return length['simpleText']?.toString() ??
          _firstRunText(Map<String, dynamic>.from(length));
    }
    return null;
  }

  String? _extractTitleText(Map<String, dynamic> renderer) {
    final title = renderer['title'];
    if (title is Map) {
      return title['simpleText']?.toString() ??
          _firstRunText(Map<String, dynamic>.from(title));
    }
    return null;
  }

  String? _firstRunText(Map<String, dynamic> textMap) {
    final runs = textMap['runs'];
    if (runs is List && runs.isNotEmpty) {
      return runs.first['text']?.toString();
    }
    return null;
  }

  Duration? _parseDuration(String? text) {
    if (text == null || text.isEmpty) return null;
    final parts = text.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    final nums = parts.map((p) => p!).toList();
    if (nums.length == 2) {
      return Duration(minutes: nums[0], seconds: nums[1]);
    } else if (nums.length == 3) {
      return Duration(hours: nums[0], minutes: nums[1], seconds: nums[2]);
    }
    return null;
  }

  Future<({String url, String userAgent})?> _tryClients(
    _CachedConfig config,
    String videoId, {
    required bool verifyStream,
  }) async {
    final clientsToTry = _clientsForRuntime();
    if (_lastSuccessfulClient != null) {
      clientsToTry.remove(_lastSuccessfulClient);
      clientsToTry.insert(0, _lastSuccessfulClient!);
    }

    for (final client in clientsToTry) {
      if (client.requiresVisitorData &&
          (config.visitorData == null || config.visitorData!.isEmpty)) {
        continue;
      }
      try {
        final player = await _fetchPlayer(config, videoId, client);
        final status = _str(_map(player['playabilityStatus']), 'status');
        if (status == 'LOGIN_REQUIRED') {
          _log('${client.key}: LOGIN_REQUIRED');
          continue;
        }
        final reason = _str(_map(player['playabilityStatus']), 'reason');
        if (reason != null && reason.toLowerCase().contains('age')) {
          _log('${client.key}: age-restricted');
          continue;
        }

        final streamingData = _map(player['streamingData']);
        if (streamingData == null) continue;

        final candidates = _audioCandidates(streamingData);
        for (final best in candidates) {
          if (best.isExpiredSoon) {
            _log('${client.key}: skipped expired stream URL');
            continue;
          }
          final playable = await YoutubeStreamHttp.probe(
            best.url,
            userAgent: client.userAgent,
            timeout: const Duration(milliseconds: 1500),
          );
          if (!playable) {
            _log('${client.key}: stream probe rejected ${best.label}');
            continue;
          }
          _streamCache[videoId] = _CachedStream(
            best.url,
            best.expiresAt,
            client.userAgent,
          );
          _lastSuccessfulClient = client;
          return (url: best.url, userAgent: client.userAgent);
        }
      } catch (e) {
        _log('${client.key} failed: $e');
      }
    }
    return null;
  }

  List<_YtClient> _clientsForRuntime() {
    const preferred = <String>[
      'ios',
      'android',
      'mweb',
    ];

    final ordered = <_YtClient>[];
    for (final key in preferred) {
      final matches = _clients.where((client) => client.key == key);
      ordered.addAll(matches);
    }
    for (final client in _clients) {
      if (!ordered.contains(client)) ordered.add(client);
    }
    return ordered;
  }

  Map<String, String> _commonHeaders(_CachedConfig config, _YtClient client) {
    return {
      'Content-Type': 'application/json',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Origin': 'https://www.youtube.com',
      'Referer': 'https://www.youtube.com/',
      'User-Agent': client.userAgent,
      'X-YouTube-Client-Name': client.id,
      'X-YouTube-Client-Version': client.version,
      if (config.visitorData != null && config.visitorData!.isNotEmpty)
        'X-Goog-Visitor-Id': config.visitorData!,
    };
  }

  Future<Map<String, dynamic>> _fetchPlayer(
    _CachedConfig config,
    String videoId,
    _YtClient client,
  ) async {
    final uri = Uri.parse(
      'https://www.youtube.com/youtubei/v1/player?key=${Uri.encodeQueryComponent(config.apiKey)}',
    );

    final headers = _commonHeaders(config, client);

    final context = <String, dynamic>{'client': client.context};

    final body = jsonEncode({
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
      'context': context,
      'playbackContext': {
        'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
      },
    });

    final resp = await http
        .post(uri, headers: headers, body: body)
        .timeout(_requestTimeout);

    if (resp.statusCode != 200) {
      throw StateError('player API ${client.key} failed (${resp.statusCode})');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  List<_AudioCandidate> _audioCandidates(Map<String, dynamic> streamingData) {
    final adaptive = _listOfMaps(streamingData['adaptiveFormats']);
    final progressive = _listOfMaps(streamingData['formats']);

    final candidates = <_AudioCandidate>[];
    // Prefer adaptive audio-only streams (smaller, higher quality per byte).
    for (final f in adaptive) {
      final mime = _str(f, 'mimeType') ?? '';
      if (!mime.contains('audio/')) continue;

      final url = _usableUrl(f);
      if (url == null || url.isEmpty) continue;

      final bitrate = (_num(f, 'bitrate') ?? _num(f, 'averageBitrate') ?? 0)
          .toDouble();
      candidates.add(
        _AudioCandidate(
          url,
          bitrate,
          _expiresAt(url),
          audioOnly: true,
          label: 'itag ${_str(f, 'itag') ?? '?'} $mime',
        ),
      );
    }

    // Fallback: progressive (video+audio muxed) as a last resort.
    for (final f in progressive) {
      final url = _usableUrl(f);
      if (url == null || url.isEmpty) continue;

      final bitrate = (_num(f, 'bitrate') ?? _num(f, 'averageBitrate') ?? 0)
          .toDouble();
      final mime = _str(f, 'mimeType') ?? 'muxed';
      candidates.add(
        _AudioCandidate(
          url,
          bitrate,
          _expiresAt(url),
          audioOnly: false,
          label: 'itag ${_str(f, 'itag') ?? '?'} $mime',
        ),
      );
    }
    candidates.sort((a, b) {
      if (a.audioOnly != b.audioOnly) return a.audioOnly ? -1 : 1;
      return b.bitrate.compareTo(a.bitrate);
    });
    return candidates;
  }

  /// Extracts a usable URL from a format map.
  ///
  /// If the format has a plain `url`, returns it. Cipher variants that need JS
  /// execution are ignored because we don't ship a JS interpreter.
  String? _usableUrl(Map<String, dynamic> format) {
    final plain = _str(format, 'url');
    if (plain != null && plain.isNotEmpty) return plain;

    final cipher = _str(format, 'signatureCipher') ?? _str(format, 'cipher');
    if (cipher == null || cipher.isEmpty) return null;

    final params = Uri.splitQueryString(cipher);
    final url = params['url'];
    if (url == null || url.isEmpty) return null;

    // `s` is a ciphered signature, not a usable signature. Only accept direct
    // signature fields that are already valid.
    final sig = params['sig'] ?? params['signature'];
    final sigParam = params['sp'] ?? 'sig';
    if (sig != null && sig.isNotEmpty) {
      final separator = url.contains('?') ? '&' : '?';
      return '$url$separator$sigParam=${Uri.encodeQueryComponent(sig)}';
    }

    return null;
  }

  DateTime? _expiresAt(String url) {
    try {
      final expire = Uri.parse(url).queryParameters['expire'];
      final secs = int.tryParse(expire ?? '');
      if (secs == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    } catch (_) {
      return null;
    }
  }

  bool _isForced(_CachedConfig config) => config.forced;

  // --- tiny JSON helpers -----------------------------------------------------

  static Object? _dig(Object? root, List<String> keys) {
    Object? current = root;
    for (final key in keys) {
      if (current is Map) {
        current = current[key];
      } else if (current is List && int.tryParse(key) != null) {
        final idx = int.parse(key);
        if (idx < 0 || idx >= current.length) return null;
        current = current[idx];
      } else {
        return null;
      }
    }
    return current;
  }

  static Map<String, dynamic>? _map(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static List<Map<String, dynamic>> _listOfMaps(Object? v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static String? _str(Map<String, dynamic>? m, String key) =>
      m == null ? null : m[key]?.toString();

  static num? _num(Map<String, dynamic>? m, String key) {
    if (m == null) return null;
    final v = m[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static void _log(String msg) {
    if (kDebugMode) debugPrint('[$_tag] $msg');
  }

  /// Returns canonical variant tags for a pre-normalised title string
  /// (lower-cased, non-[a-z0-9_\s] stripped — same form used for scoring).
  static Set<String> _detectVariants(String norm) {
    final tags = <String>{};

    // 8D / Spatial audio (most jarring mismatch)
    if (RegExp(
      r'\b(8d|16d|spatial\saudio?|binaural|360|surround)\b',
    ).hasMatch(norm)) {
      tags.add('8d');
    }

    // Slowed / Reverb
    if (RegExp(r'\b(slowed|reverb)\b').hasMatch(norm)) {
      tags.add('slowed_reverb');
    }

    // Nightcore / Sped-up
    if (RegExp(r'\b(nightcore|sped[\s]?up)\b').hasMatch(norm)) {
      tags.add('nightcore');
    }

    // Lo-fi
    if (RegExp(r'\blo[\s]?fi\b').hasMatch(norm)) {
      tags.add('lofi');
    }

    // Instrumental / Karaoke
    if (RegExp(
      r'\b(instrumental|karaoke|no\svo[ck]als?|backing\strack)\b',
    ).hasMatch(norm)) {
      tags.add('instrumental');
    }

    // Remix / Mashup / Bootleg
    if (RegExp(
      r'\b(remix|mashup|bootleg|flip|vip\smix|reedit)\b',
    ).hasMatch(norm)) {
      tags.add('remix');
    }

    // Live
    if (RegExp(
      r'\b(live\b|in\sconcert|live\sat|live\sfrom)\b',
    ).hasMatch(norm)) {
      tags.add('live');
    }

    // Acoustic / Unplugged
    if (RegExp(r'\b(acoustic|unplugged)\b').hasMatch(norm)) {
      tags.add('acoustic');
    }

    // Cover
    if (RegExp(r'\bcover\b').hasMatch(norm)) {
      tags.add('cover');
    }

    // Extended mix
    if (RegExp(r'\b(extended\s(mix|version)|full\sversion)\b').hasMatch(norm)) {
      tags.add('extended');
    }

    return tags;
  }

  // Penalty weights — higher = more jarring if wrong
  static const Map<String, double> _variantPenalties = {
    '8d': 700.0,
    'slowed_reverb': 600.0,
    'nightcore': 600.0,
    'lofi': 500.0,
    'instrumental': 500.0,
    'remix': 400.0,
    'cover': 400.0,
    'live': 300.0,
    'acoustic': 300.0,
    'extended': 200.0,
  };
}

// --- private types -----------------------------------------------------------

class _YtClient {
  final String key;
  final String id;
  final String version;
  final String userAgent;
  final Map<String, Object> context;
  final bool requiresVisitorData;

  _YtClient({
    required this.key,
    required this.id,
    required this.version,
    required this.userAgent,
    required this.context,
    this.requiresVisitorData = false,
  });
}

class _CachedConfig {
  final String apiKey;
  final String? visitorData;
  final DateTime fetchedAt;
  final bool forced;

  _CachedConfig({
    required this.apiKey,
    required this.visitorData,
    this.forced = false,
  }) : fetchedAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) >= YoutubeAudioExtractor._configTtl;
}

class _CachedVideoIds {
  final List<String> videoIds;
  final DateTime cachedAt;

  _CachedVideoIds(List<String> videoIds)
    : videoIds = List<String>.unmodifiable(videoIds),
      cachedAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(cachedAt) >= const Duration(hours: 12);
}

class _CachedStream {
  final String url;
  final DateTime? expiresAt;
  final DateTime cachedAt;
  final String userAgent;

  _CachedStream(this.url, this.expiresAt, this.userAgent)
    : cachedAt = DateTime.now();

  bool get isExpired {
    final exp = expiresAt;
    if (exp != null) {
      // Expire 60s early to avoid racing the CDN.
      return DateTime.now().isAfter(exp.subtract(const Duration(seconds: 60)));
    }
    return DateTime.now().difference(cachedAt) >= const Duration(hours: 4);
  }
}

class _AudioCandidate {
  final String url;
  final double bitrate;
  final DateTime? expiresAt;
  final bool audioOnly;
  final String label;

  _AudioCandidate(
    this.url,
    this.bitrate,
    this.expiresAt, {
    required this.audioOnly,
    required this.label,
  });

  bool get isExpiredSoon {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp.subtract(const Duration(minutes: 2)));
  }
}

class _VideoCandidate {
  final String id;
  final String title;
  final Duration? duration;
  final bool isLive;

  _VideoCandidate({
    required this.id,
    required this.title,
    this.duration,
    this.isLive = false,
  });
}
