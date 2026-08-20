import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 1-to-1 Port of NuvioTV InAppYouTubeExtractor for Audio Streams.
///
/// Features:
/// 1. VisionOS (101), Android (3), and iOS (5) InnerTube clients.
/// 2. Automatic watch page scraping for INNERTUBE_API_KEY and VISITOR_DATA.
/// 3. 3-hour cache TTL with auto-invalidation on LOGIN_REQUIRED.
/// 4. Precise candidate scoring (bitrate * 1e6 + audioSampleRate), non-nParam preference,
///    container ranking (m4a > webm), and client priority hierarchy.
/// 5. Multi-node CDN redundancy probing (parsing `mn` param to find the fastest reachable host).
class YoutubeAudioExtractor {
  YoutubeAudioExtractor._();
  static final YoutubeAudioExtractor instance = YoutubeAudioExtractor._();

  static const String _tag = 'YoutubeAudioExtractor';

  static const String _fallbackApiKey =
      'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  static const Duration _configTtl = Duration(hours: 3);
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const int _maxVideoCandidates = 2;

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 12; Android TV) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

  // Search client context: WEB is most reliable for InnerTube search queries.
  static final _YtClient _searchClient = _YtClient(
    key: 'web_search',
    id: '1',
    version: '2.20250217.03.00',
    userAgent: _defaultUserAgent,
    context: {
      'clientName': 'WEB',
      'clientVersion': '2.20250217.03.00',
      'hl': 'en',
      'gl': 'US',
      'platform': 'DESKTOP',
    },
    priority: 99,
  );

  // 1-to-1 Match with NuvioTV CLIENTS hierarchy
  static final List<_YtClient> _clients = [
    // 1. visionOS (Priority 0 - Highest, unthrottled, no cipher)
    _YtClient(
      key: 'visionos',
      id: '101',
      version: '1.02',
      userAgent:
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      context: {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'hl': 'en',
        'gl': 'US',
      },
      priority: 0,
    ),
    // 2. Android (Priority 1)
    _YtClient(
      key: 'android',
      id: '3',
      version: '20.10.35',
      userAgent:
          'com.google.android.youtube/20.10.35 (Linux; U; Android 14; en_US) gzip',
      context: {
        'clientName': 'ANDROID',
        'clientVersion': '20.10.35',
        'osName': 'Android',
        'osVersion': '14',
        'platform': 'MOBILE',
        'androidSdkVersion': 34,
        'hl': 'en',
        'gl': 'US',
      },
      priority: 1,
    ),
    // 3. iOS (Priority 2)
    _YtClient(
      key: 'ios',
      id: '5',
      version: '20.10.1',
      userAgent:
          'com.google.ios.youtube/20.10.1 (iPhone16,2; U; CPU iOS 17_4 like Mac OS X)',
      context: {
        'clientName': 'IOS',
        'clientVersion': '20.10.1',
        'deviceModel': 'iPhone16,2',
        'osName': 'iPhone',
        'osVersion': '17.4.0.21E219',
        'platform': 'MOBILE',
        'hl': 'en',
        'gl': 'US',
      },
      priority: 2,
    ),
  ];

  // --- State ---
  _CachedConfig? _config;
  Future<_CachedConfig>? _configInFlight;

  final Map<String, _CachedVideoIds> _videoIdCache = {};
  final Map<String, _CachedStream> _streamCache = {};

  // ===========================================================================
  // Public API
  // ===========================================================================

  /// Search YouTube for [title] + [artist] and return the best ranked videoId.
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
      suffix = 'official audio';
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

  /// Resolve a plaintext audio URL for [videoId] using NuvioTV extraction logic.
  Future<({String url, String userAgent})?> getAudioUrl(
    String videoId, {
    bool verifyStream = true,
  }) async {
    final cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) {
      return (url: cached.url, userAgent: cached.userAgent);
    }

    var result = await _extractAudioInternal(videoId, forceRefreshConfig: false);
    if (result == null) {
      _log('First extraction attempt failed for $videoId, retrying with fresh config...');
      result = await _extractAudioInternal(videoId, forceRefreshConfig: true);
    }

    if (result != null) {
      _streamCache[videoId] = _CachedStream(
        result.url,
        _expiresAt(result.url),
        result.userAgent,
      );
    }

    return result;
  }

  /// One-shot extraction helper: searches and resolves audio URL.
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
  // 1-to-1 NuvioTV Audio Extraction Engine
  // ===========================================================================

  Future<({String url, String userAgent})?> _extractAudioInternal(
    String videoId, {
    required bool forceRefreshConfig,
  }) async {
    final config = await _ensureConfig(forceRefresh: forceRefreshConfig);
    final candidates = <_NuvioAudioCandidate>[];
    int loginRequiredCount = 0;

    for (final client in _clients) {
      try {
        final player = await _fetchPlayer(config, videoId, client);
        final playabilityStatus = _map(player['playabilityStatus']);
        final status = _str(playabilityStatus, 'status');

        if (status == 'LOGIN_REQUIRED') {
          loginRequiredCount++;
          _log('Client ${client.key}: LOGIN_REQUIRED');
          continue;
        }
        if (status != null && status != 'OK') {
          continue;
        }

        final streamingData = _map(player['streamingData']);
        if (streamingData == null) continue;

        final adaptiveFormats = _listOfMaps(streamingData['adaptiveFormats']);
        for (final format in adaptiveFormats) {
          final url = _usableUrl(format);
          if (url == null || url.isEmpty) continue;
          final mimeType = _str(format, 'mimeType')?.toLowerCase() ?? '';
          if (!mimeType.contains('audio/')) continue;

          final bitrate = (_num(format, 'bitrate') ?? _num(format, 'averageBitrate') ?? 0).toDouble();
          final asr = double.tryParse(_str(format, 'audioSampleRate') ?? '') ?? 0.0;
          final score = (bitrate * 1000000.0) + asr;
          final hasN = _hasNParam(url);
          final ext = mimeType.contains('webm') ? 'webm' : 'm4a';

          candidates.add(_NuvioAudioCandidate(
            clientKey: client.key,
            clientPriority: client.priority,
            userAgent: client.userAgent,
            url: url,
            score: score,
            hasN: hasN,
            itag: _str(format, 'itag') ?? '',
            bitrate: bitrate,
            ext: ext,
          ));
        }

        // Also check progressive formats as secondary fallback
        final formats = _listOfMaps(streamingData['formats']);
        for (final format in formats) {
          final url = _usableUrl(format);
          if (url == null || url.isEmpty) continue;
          final bitrate = (_num(format, 'bitrate') ?? _num(format, 'averageBitrate') ?? 0).toDouble();
          final hasN = _hasNParam(url);

          candidates.add(_NuvioAudioCandidate(
            clientKey: client.key,
            clientPriority: client.priority,
            userAgent: client.userAgent,
            url: url,
            score: bitrate, // lower score than adaptive
            hasN: hasN,
            itag: _str(format, 'itag') ?? '',
            bitrate: bitrate,
            ext: 'mp4',
          ));
        }
      } catch (e) {
        _log('Client ${client.key} failed: $e');
      }
    }

    if (loginRequiredCount == _clients.length) {
      _log('All ${_clients.length} clients returned LOGIN_REQUIRED, invalidating config');
      _config = null;
      return null;
    }

    if (candidates.isEmpty) return null;

    // NuvioTV Sort Hierarchy:
    // 1. Higher score first
    // 2. without 'n' param first
    // 3. m4a over webm
    // 4. client priority (visionos > android > ios)
    candidates.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      final n = (a.hasN ? 1 : 0).compareTo(b.hasN ? 1 : 0);
      if (n != 0) return n;
      final c = a.containerPreference.compareTo(b.containerPreference);
      if (c != 0) return c;
      return a.clientPriority.compareTo(b.clientPriority);
    });

    // Probing & CDN resolution
    for (final best in candidates) {
      final reachableUrl = await _resolveReachableUrl(best.url, userAgent: best.userAgent);
      if (reachableUrl != null) {
        _log('Resolved reachable audio URL (client=${best.clientKey}, itag=${best.itag}, ext=${best.ext})');
        return (url: reachableUrl, userAgent: best.userAgent);
      }
    }

    return null;
  }

  /// Probes CDN nodes for the given googlevideo URL and returns the first reachable one.
  /// Generates alternate hosts based on YouTube's `mn` parameter.
  Future<String?> _resolveReachableUrl(String url, {required String userAgent}) async {
    if (!url.contains('googlevideo.com')) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    final mnParam = uri.queryParameters['mn'];
    if (mnParam == null || mnParam.isEmpty) {
      return await _isUrlReachable(url, userAgent: userAgent) ? url : null;
    }

    final servers = mnParam.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (servers.length < 2) {
      return await _isUrlReachable(url, userAgent: userAgent) ? url : null;
    }

    final candidates = <String>[url];
    for (int i = 0; i < servers.length; i++) {
      final server = servers[i];
      final currentHost = uri.host;
      final altHost = currentHost
          .replaceFirst(RegExp(r'^rr\d+---'), 'rr${i + 1}---')
          .replaceFirst(RegExp(r'sn-[a-z0-9]+-[a-z0-9]+'), server);

      if (altHost != currentHost) {
        candidates.add(url.replaceFirst(currentHost, altHost));
      }
    }

    if (candidates.length == 1) {
      return await _isUrlReachable(candidates[0], userAgent: userAgent) ? candidates[0] : null;
    }

    final completer = Completer<String?>();
    var completed = false;

    for (final cand in candidates) {
      _isUrlReachable(cand, userAgent: userAgent).then((reachable) {
        if (reachable && !completed && !completer.isCompleted) {
          completed = true;
          completer.complete(cand);
        }
      });
    }

    return await completer.future.timeout(
      const Duration(milliseconds: 2000),
      onTimeout: () => _isUrlReachable(candidates.first, userAgent: userAgent).then((ok) => ok ? candidates.first : null),
    );
  }

  Future<bool> _isUrlReachable(String url, {required String userAgent}) async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Range': 'bytes=0-0',
          'User-Agent': userAgent,
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(milliseconds: 1500));
      return res.statusCode == 200 || res.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  static bool _hasNParam(String url) {
    try {
      return Uri.parse(url).queryParameters.containsKey('n');
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // Config & InnerTube Requests
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
              'User-Agent': _defaultUserAgent,
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
    final start = idx + key.length + 4;
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

      // 3. Variant matching
      final candVariants = _detectVariants(normCandTitle);
      final allVariants = <String>{...targetVariants, ...candVariants};
      for (final tag in allVariants) {
        if (targetVariants.contains(tag) == candVariants.contains(tag)) {
          score += 15.0;
        } else {
          score -= _variantPenalties[tag] ?? 350.0;
        }
      }

      // 4. Duration match
      if (targetDuration != null && candDuration != null) {
        final diffSecs = (candDuration.inSeconds - targetDuration.inSeconds).abs();
        if (diffSecs <= 4) {
          score += 80.0;
        } else if (diffSecs <= 10) {
          score += 25.0;
        } else if (diffSecs <= 20) {
          score += 5.0;
        } else if (diffSecs <= 40) {
          score -= diffSecs * 2.0;
        } else {
          score -= diffSecs * 5.0;
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

  String? _usableUrl(Map<String, dynamic> format) {
    final plain = _str(format, 'url');
    if (plain != null && plain.isNotEmpty) return plain;

    final cipher = _str(format, 'signatureCipher') ?? _str(format, 'cipher');
    if (cipher == null || cipher.isEmpty) return null;

    final params = Uri.splitQueryString(cipher);
    final url = params['url'];
    if (url == null || url.isEmpty) return null;

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

  static Set<String> _detectVariants(String norm) {
    final tags = <String>{};

    if (RegExp(r'\b(8d|16d|spatial\saudio?|binaural|360|surround)\b').hasMatch(norm)) {
      tags.add('8d');
    }
    if (RegExp(r'\b(slowed|reverb)\b').hasMatch(norm)) {
      tags.add('slowed_reverb');
    }
    if (RegExp(r'\b(nightcore|sped[\s]?up)\b').hasMatch(norm)) {
      tags.add('nightcore');
    }
    if (RegExp(r'\blo[\s]?fi\b').hasMatch(norm)) {
      tags.add('lofi');
    }
    if (RegExp(r'\b(instrumental|karaoke|no\svo[ck]als?|backing\strack)\b').hasMatch(norm)) {
      tags.add('instrumental');
    }
    if (RegExp(r'\b(remix|mashup|bootleg|flip|vip\smix|reedit)\b').hasMatch(norm)) {
      tags.add('remix');
    }
    if (RegExp(r'\b(live\b|in\sconcert|live\sat|live\sfrom)\b').hasMatch(norm)) {
      tags.add('live');
    }
    if (RegExp(r'\b(acoustic|unplugged)\b').hasMatch(norm)) {
      tags.add('acoustic');
    }
    if (RegExp(r'\bcover\b').hasMatch(norm)) {
      tags.add('cover');
    }
    if (RegExp(r'\b(extended\s(mix|version)|full\sversion)\b').hasMatch(norm)) {
      tags.add('extended');
    }

    return tags;
  }

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
  final int priority;

  _YtClient({
    required this.key,
    required this.id,
    required this.version,
    required this.userAgent,
    required this.context,
    required this.priority,
  });
}

class _NuvioAudioCandidate {
  final String clientKey;
  final int clientPriority;
  final String userAgent;
  final String url;
  final double score;
  final bool hasN;
  final String itag;
  final double bitrate;
  final String ext;

  _NuvioAudioCandidate({
    required this.clientKey,
    required this.clientPriority,
    required this.userAgent,
    required this.url,
    required this.score,
    required this.hasN,
    required this.itag,
    required this.bitrate,
    required this.ext,
  });

  int get containerPreference {
    switch (ext.toLowerCase()) {
      case 'm4a':
      case 'mp4':
        return 0;
      case 'webm':
        return 1;
      default:
        return 2;
    }
  }
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
      return DateTime.now().isAfter(exp.subtract(const Duration(seconds: 60)));
    }
    return DateTime.now().difference(cachedAt) >= const Duration(hours: 4);
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
