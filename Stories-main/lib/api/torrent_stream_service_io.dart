import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:path/path.dart' as p;
import 'settings_service.dart';
import 'torrent_filter.dart';

/// Rich torrent statistics object.
class TorrentStats {
  final double speedMbps;
  final int activePeers;
  final int totalPeers;
  final double cachePercent;
  final int loadedBytes;
  final int totalBytes;
  final String hash;
  final bool isConnected;

  const TorrentStats({
    required this.speedMbps,
    required this.activePeers,
    required this.totalPeers,
    required this.cachePercent,
    required this.loadedBytes,
    required this.totalBytes,
    required this.hash,
    required this.isConnected,
  });

  double get speedKbps => speedMbps * 1024;
  String get speedLabel => speedMbps >= 1.0
      ? '${speedMbps.toStringAsFixed(2)} MB/s'
      : '${speedKbps.toStringAsFixed(0)} KB/s';
  String get peersLabel => '$activePeers / $totalPeers';
  String get cacheLabel => '${cachePercent.toStringAsFixed(1)}%';
}

/// Engine lifecycle states.
enum EngineState { stopped, starting, ready, error }

/// Drop-in replacement for TorrServerService using libtorrent_flutter.
///
/// Same public API:
///   start(), streamTorrent(), removeTorrent(), getTorrentStats(),
///   statsStream(), stop(), cleanup()
class TorrentStreamService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final TorrentStreamService _instance = TorrentStreamService._internal();
  factory TorrentStreamService() => _instance;
  TorrentStreamService._internal();

  // ── State ──────────────────────────────────────────────────────────────────
  EngineState _state = EngineState.stopped;
  EngineState get state => _state;

  void Function(EngineState state)? onStateChanged;
  void Function(String line)? onLogLine;

  /// Active torrent IDs keyed by info-hash for cleanup.
  final Map<String, int> _activeTorrents = {};

  /// Active stream IDs keyed by info-hash for cleanup (video / single stream).
  final Map<String, int> _activeStreams = {};

  /// Audiobook chapter streams: info-hash → file index → stream id.
  final Map<String, Map<int, int>> _audiobookStreamsByFile = {};

  /// Cached loopback URLs for active audiobook streams.
  final Map<String, Map<int, String>> _audiobookStreamUrls = {};

  /// Track disposed torrent/stream IDs to prevent double-dispose native crash.
  final Set<int> _disposedTorrentIds = {};
  final Set<int> _disposedStreamIds = {};

  StreamSubscription? _torrentUpdatesSub;

  /// Latest torrent update snapshots keyed by torrent ID.
  final Map<int, TorrentInfo> _latestUpdates = {};

  final SettingsService _settings = SettingsService();

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Initialises the libtorrent engine. Safe to call multiple times.
  Future<bool> start() async {
    if (_state == EngineState.ready) return true;
    if (_state == EngineState.starting) {
      // Wait for init to finish
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_state == EngineState.ready) return true;
        if (_state == EngineState.error) return false;
      }
      return false;
    }

    _setState(EngineState.starting);
    try {
      await LibtorrentFlutter.init();
      _torrentUpdatesSub = LibtorrentFlutter.instance.torrentUpdates.listen((updates) {
        _latestUpdates.addAll(updates);
      });
      _setState(EngineState.ready);
      _log('Engine ready (libtorrent_flutter)');
      return true;
    } catch (e, st) {
      _log('Failed to start engine: $e\n$st');
      _setState(EngineState.error);
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stream a torrent — main entry point
  // ─────────────────────────────────────────────────────────────────────────

  /// Adds a magnet, waits for metadata, selects the right file, starts an
  /// HTTP stream, and returns the stream URL.
  ///
  /// Matches the old TorrServerService.streamTorrent() signature exactly.
  Future<String?> streamTorrent(
    String magnetLink, {
    int? season,
    int? episode,
    int? fileIdx,
  }) async {
    if (_state != EngineState.ready) {
      final started = await start();
      if (!started) {
        _log('Cannot stream: engine failed to start.');
        return null;
      }
    }

    final hash = _extractHash(magnetLink);

    // Dispose previous torrent with same hash if any
    if (hash != null && _activeTorrents.containsKey(hash)) {
      try {
        final oldId = _activeTorrents[hash]!;
        if (_activeStreams.containsKey(hash)) {
          _safeStopStream(_activeStreams[hash]!);
          _activeStreams.remove(hash);
        }
        _stopAudiobookStreamsForMapKey(hash ?? magnetLink);
        _safeDisposeTorrent(oldId);
        _activeTorrents.remove(hash);
      } catch (e) {
        _log('Cleanup old torrent error: $e');
      }
    }

    try {
      // Step 1: Read cache settings
      final cacheType = await _settings.getTorrentCacheType();
      final ramCacheMb = await _settings.getTorrentRamCacheMb();
      final saveToRam = cacheType == 'ram';

      // Step 2: Add the magnet
      final torrentId = LibtorrentFlutter.instance.addMagnet(magnetLink, null, saveToRam);
      if (hash != null) {
        _activeTorrents[hash] = torrentId;
      }
      _log('Added magnet, torrentId=$torrentId');

      // Step 3: Wait for metadata
      final files = await _waitForMetadata(torrentId);
      if (files == null || files.isEmpty) {
        _log('No files found in torrent');
        return null;
      }

      // Step 4: Select the right file
      final selectedIndex = _selectFile(files, season: season, episode: episode, preferredIdx: fileIdx);
      if (selectedIndex == null) {
        _log('No suitable video file found');
        return null;
      }

      _log('Selected file index $selectedIndex: ${files.firstWhere((f) => f.index == selectedIndex).name}');

      // Step 5: Start the stream
      final maxCacheBytes = saveToRam ? (ramCacheMb * 1024 * 1024) : 0;
      final streamInfo = LibtorrentFlutter.instance.startStream(
        torrentId,
        fileIndex: selectedIndex,
        maxCacheBytes: maxCacheBytes,
      );

      if (hash != null) {
        _activeStreams[hash] = streamInfo.id;
      }

      _log('Stream started: ${streamInfo.url}');
      return streamInfo.url;
    } catch (e) {
      _log('streamTorrent error: $e');
      return null;
    }
  }

  /// HTTP stream URL for one torrent file — keeps the torrent loaded so multiple
  /// files (audiobook chapters) can be streamed without re-adding the magnet.
  Future<String?> streamAudiobookFile(
    String magnetLink,
    int fileIdx, {
    bool allowNonStreamable = false,
    bool stopSiblingStreams = true,
    String? fileNameHint,
    bool primeBuffer = false,
  }) async {
    if (_state != EngineState.ready) {
      final started = await start();
      if (!started) {
        _log('Audiobook stream: engine failed to start.');
        return null;
      }
    }

    final hash = _extractHash(magnetLink);
    final key = hash ?? magnetLink;

    final cacheType = await _settings.getTorrentCacheType();
    final ramCacheMb = await _settings.getTorrentRamCacheMb();
    final saveToRam = cacheType == 'ram';
    final maxCacheBytes = saveToRam ? (ramCacheMb * 1024 * 1024) : 0;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        late final int torrentId;
        if (hash != null && _activeTorrents.containsKey(hash)) {
          torrentId = _activeTorrents[hash]!;
        } else {
          torrentId =
              LibtorrentFlutter.instance.addMagnet(magnetLink, null, saveToRam);
          if (hash != null) {
            _activeTorrents[hash] = torrentId;
          }
          _log('Audiobook: added magnet, torrentId=$torrentId');
          final metaFiles = await _waitForMetadata(torrentId);
          if (metaFiles == null || metaFiles.isEmpty) {
            _log('Audiobook: no files in torrent');
            if (hash != null) {
              _safeDisposeTorrent(torrentId);
              _activeTorrents.remove(hash);
            } else {
              _safeDisposeTorrent(torrentId);
            }
            return null;
          }
        }

        final files = LibtorrentFlutter.instance.getFiles(torrentId);
        if (files.isEmpty) {
          _log('Audiobook: empty file list torrentId=$torrentId');
          if (attempt == 0 && hash != null) {
            _disposeTorrentForAudiobookRetry(hash, key);
            continue;
          }
          return null;
        }

        final fi = _resolveAudiobookFileInfo(
          files,
          fileIdx,
          fileNameHint,
          allowNonStreamable,
        );
        if (fi == null) {
          _log(
            'Audiobook: no match idx=$fileIdx hint=$fileNameHint '
            'files=${files.map((f) => '${f.index}:${p.basename(f.name)}').join(', ')}',
          );
          return null;
        }

        final streamIdx = fi.index;

        if (stopSiblingStreams) {
          _stopAudiobookStreamsForMapKey(key);
        }

        final byFile = _audiobookStreamsByFile.putIfAbsent(key, () => {});
        final cachedUrl = _audiobookStreamUrls[key]?[streamIdx];
        if (!stopSiblingStreams &&
            byFile.containsKey(streamIdx) &&
            cachedUrl != null &&
            cachedUrl.isNotEmpty) {
          _log('Audiobook stream cache hit idx=$streamIdx');
          return cachedUrl;
        }

        if (!stopSiblingStreams) {
          final oldSid = byFile[streamIdx];
          if (oldSid != null) {
            _safeStopStream(oldSid);
          }
        }

        try {
          final streamInfo = LibtorrentFlutter.instance.startStream(
            torrentId,
            fileIndex: streamIdx,
            maxCacheBytes: maxCacheBytes,
          );
          byFile[streamIdx] = streamInfo.id;
          _audiobookStreamUrls.putIfAbsent(key, () => {})[streamIdx] =
              streamInfo.url;
          _log(
            'Audiobook stream started idx=$streamIdx file=${fi.name} → ${streamInfo.url}',
          );
          if (primeBuffer) {
            await _primeAudiobookStreamUrl(streamInfo.url);
          }
          return streamInfo.url;
        } catch (e) {
          _log('Audiobook startStream failed (attempt $attempt): $e');
          if (attempt == 0 && hash != null) {
            _disposeTorrentForAudiobookRetry(hash, key);
            continue;
          }
          return null;
        }
      } catch (e) {
        _log('streamAudiobookFile error: $e');
        if (attempt == 0 && hash != null) {
          _disposeTorrentForAudiobookRetry(hash, key);
          continue;
        }
        return null;
      }
    }
    return null;
  }

  /// Adds a magnet and waits for metadata so the player can start streaming sooner.
  Future<bool> prefetchAudiobookMagnet(String magnetLink) async {
    if (_state != EngineState.ready) {
      if (!await start()) return false;
    }

    final hash = _extractHash(magnetLink);
    try {
      final cacheType = await _settings.getTorrentCacheType();
      final saveToRam = cacheType == 'ram';

      late final int torrentId;
      if (hash != null && _activeTorrents.containsKey(hash)) {
        torrentId = _activeTorrents[hash]!;
        final existing = LibtorrentFlutter.instance.getFiles(torrentId);
        if (existing.isNotEmpty) return true;
      } else {
        torrentId =
            LibtorrentFlutter.instance.addMagnet(magnetLink, null, saveToRam);
        if (hash != null) {
          _activeTorrents[hash] = torrentId;
        }
        _log('Audiobook prefetch: added magnet, torrentId=$torrentId');
      }

      final files = await _waitForMetadata(
        torrentId,
        timeout: const Duration(seconds: 25),
      );
      return files != null && files.isNotEmpty;
    } catch (e) {
      _log('prefetchAudiobookMagnet error: $e');
      return false;
    }
  }

  /// Warms the HTTP stream for one chapter so playback can open immediately.
  Future<String?> prefetchAudiobookChapter(
    String magnetLink,
    int fileIdx, {
    String? fileNameHint,
  }) {
    return streamAudiobookFile(
      magnetLink,
      fileIdx,
      allowNonStreamable: true,
      stopSiblingStreams: false,
      fileNameHint: fileNameHint,
      primeBuffer: true,
    );
  }

  /// Pull the first chunk through the loopback stream so mpv can start sooner.
  Future<void> _primeAudiobookStreamUrl(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      final res = await req.close().timeout(const Duration(seconds: 5));
      var received = 0;
      const targetBytes = 384 * 1024;
      await for (final chunk in res) {
        received += chunk.length;
        if (received >= targetBytes) break;
      }
      _log('Primed stream buffer (~${received ~/ 1024} KB)');
    } catch (e) {
      _log('Stream prime skipped: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// Stops audiobook streams and drops the torrent for this magnet.
  void releaseAudiobookMagnet(String magnetLink) {
    removeTorrent(magnetLink);
  }

  /// Stops HTTP streams for audiobook files only (torrent stays in session).
  void stopAudiobookStreamsForMagnet(String magnetLink) {
    final hash = _extractHash(magnetLink);
    final key = hash ?? magnetLink;
    _stopAudiobookStreamsForMapKey(key);
  }

  /// Dispose a torrent opened elsewhere (e.g. magnet picker preview) that was
  /// never registered in [_activeTorrents].
  void disposeOrphanTorrent(int torrentId) {
    _safeDisposeTorrent(torrentId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Metadata polling
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<FileInfo>?> _waitForMetadata(int torrentId, {Duration timeout = const Duration(seconds: 30)}) async {
    final completer = Completer<List<FileInfo>?>();
    StreamSubscription? sub;
    var polls = 0;

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _log('Metadata timeout after ${timeout.inSeconds}s');
        sub?.cancel();
        completer.complete(null);
      }
    });

    sub = LibtorrentFlutter.instance.torrentUpdates.listen((updates) {
      if (completer.isCompleted) return;
      if (updates.containsKey(torrentId)) {
        final info = updates[torrentId]!;
        if (info.hasMetadata) {
          timer.cancel();
          sub?.cancel();
          final files = LibtorrentFlutter.instance.getFiles(torrentId);
          completer.complete(files);
        }
      }
    });

    Future<void> poll() async {
      while (!completer.isCompleted && polls < 120) {
        polls++;
        try {
          final files = LibtorrentFlutter.instance.getFiles(torrentId);
          if (files.isNotEmpty) {
            timer.cancel();
            sub?.cancel();
            if (!completer.isCompleted) {
              completer.complete(files);
            }
            return;
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    unawaited(poll());
    return completer.future;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // File selection — same logic as old TorrServerService
  // ─────────────────────────────────────────────────────────────────────────

  int? _selectFile(List<FileInfo> files, {int? season, int? episode, int? preferredIdx}) {
    // Filter to streamable video files
    final videoFiles = files.where((f) => f.isStreamable && TorrentFilter.isVideoFile(f.name)).toList();
    if (videoFiles.isEmpty) {
      // Fallback: any streamable file
      final streamable = files.where((f) => f.isStreamable).toList();
      if (streamable.isEmpty) return null;
      streamable.sort((a, b) => b.size.compareTo(a.size));
      return streamable.first.index;
    }

    // 1. Season/episode match
    if (season != null && episode != null) {
      final episodeMatches = videoFiles
          .where((f) => TorrentFilter.isFileMatch(f.name, season, episode))
          .toList();
      if (episodeMatches.isNotEmpty) {
        // Pick largest matching file (most likely the actual episode)
        episodeMatches.sort((a, b) => b.size.compareTo(a.size));
        return episodeMatches.first.index;
      }
    }

    // 2. Preferred index from Stremio addon (if valid video)
    if (preferredIdx != null) {
      final match = videoFiles.where((f) => f.index == preferredIdx).toList();
      if (match.isNotEmpty) {
        return match.first.index;
      }
    }

    // 3. Largest video file
    videoFiles.sort((a, b) => b.size.compareTo(a.size));
    return videoFiles.first.index;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Torrent management
  // ─────────────────────────────────────────────────────────────────────────

  /// Removes/disposes a torrent and stops its streams.
  void removeTorrent(String magnetOrHash) {
    final hash = _extractHash(magnetOrHash);
    final key = hash ?? magnetOrHash;

    _stopAudiobookStreamsForMapKey(key);

    // Stop stream
    if (_activeStreams.containsKey(key)) {
      _safeStopStream(_activeStreams[key]!);
      _activeStreams.remove(key);
    }

    // Dispose torrent
    if (_activeTorrents.containsKey(key)) {
      final torrentId = _activeTorrents[key]!;
      _safeDisposeTorrent(torrentId);
      _activeTorrents.remove(key);
      _latestUpdates.remove(torrentId);
      _log('Removed torrent $key');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Statistics
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns stats for a torrent, or null if unavailable.
  TorrentStats? getTorrentStats(String magnetOrHash) {
    final hash = _extractHash(magnetOrHash);
    final key = hash ?? magnetOrHash;
    final torrentId = _activeTorrents[key];
    if (torrentId == null) return null;

    final info = _latestUpdates[torrentId];
    if (info == null) return null;

    final speedMbps = info.downloadRate / 1024 / 1024;

    return TorrentStats(
      speedMbps: speedMbps,
      activePeers: info.numPeers,
      totalPeers: info.numPeers,
      cachePercent: info.progress * 100,
      loadedBytes: info.totalDone,
      totalBytes: info.totalWanted,
      hash: key,
      isConnected: info.numPeers > 0,
    );
  }

  /// Streams stats at [interval] for a torrent.
  Stream<TorrentStats> statsStream(
    String magnetOrHash, {
    Duration interval = const Duration(seconds: 1),
  }) {
    final controller = StreamController<TorrentStats>();
    Timer? timer;

    controller.onListen = () {
      timer = Timer.periodic(interval, (_) {
        final stats = getTorrentStats(magnetOrHash);
        if (stats != null && !controller.isClosed) {
          controller.add(stats);
        }
      });
    };

    controller.onCancel = () {
      timer?.cancel();
      controller.close();
    };

    return controller.stream;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stop / cleanup
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    // Stop all active streams
    for (final streamId in _activeStreams.values) {
      _safeStopStream(streamId);
    }
    _activeStreams.clear();

    for (final byFile in _audiobookStreamsByFile.values) {
      for (final streamId in byFile.values) {
        _safeStopStream(streamId);
      }
    }
    _audiobookStreamsByFile.clear();

    // Dispose all active torrents
    for (final torrentId in _activeTorrents.values) {
      _safeDisposeTorrent(torrentId);
    }
    _activeTorrents.clear();
    _latestUpdates.clear();

    _log('All torrents stopped.');
  }

  Future<void> cleanup() async {
    await stop();
    _torrentUpdatesSub?.cancel();
    _torrentUpdatesSub = null;
    _disposedTorrentIds.clear();
    _disposedStreamIds.clear();
    _setState(EngineState.stopped);
    _log('Engine cleaned up.');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _stopAudiobookStreamsForMapKey(String mapKey) {
    final byFile = _audiobookStreamsByFile.remove(mapKey);
    _audiobookStreamUrls.remove(mapKey);
    if (byFile == null) return;
    for (final streamId in byFile.values) {
      _safeStopStream(streamId);
    }
  }

  /// Safely stop a stream, preventing double-stop native crash.
  void _safeStopStream(int streamId) {
    if (_disposedStreamIds.contains(streamId)) return;
    _disposedStreamIds.add(streamId);
    try {
      LibtorrentFlutter.instance.stopStream(streamId);
    } catch (e) {
      _log('Stop stream error: $e');
    }
  }

  /// Safely dispose a torrent, preventing double-dispose native crash.
  void _safeDisposeTorrent(int torrentId) {
    if (_disposedTorrentIds.contains(torrentId)) return;
    _disposedTorrentIds.add(torrentId);
    try {
      LibtorrentFlutter.instance.disposeTorrent(torrentId);
    } catch (e) {
      _log('Dispose torrent error: $e');
    }
  }

  static final _hashRegExp = RegExp(r'[0-9a-fA-F]{40}');

  /// Prefer explicit `btih:` from magnet URIs so we never grab an unrelated
  /// 40-char hex substring elsewhere in the string.
  String? _extractHash(String magnetOrHash) {
    final btih = RegExp(r'btih:([0-9a-fA-F]{40})', caseSensitive: false)
        .firstMatch(magnetOrHash);
    if (btih != null) return btih.group(1)!.toLowerCase();
    final match = _hashRegExp.firstMatch(magnetOrHash);
    return match?.group(0)?.toLowerCase();
  }

  /// Match [fileIdx] to libtorrent files; if missing or wrong, fall back to
  /// basename match against [fileNameHint] (chapter / cover filename).
  FileInfo? _resolveAudiobookFileInfo(
    List<FileInfo> files,
    int fileIdx,
    String? fileNameHint,
    bool allowNonStreamable,
  ) {
    FileInfo? byIndex;
    for (final f in files) {
      if (f.index == fileIdx) {
        byIndex = f;
        break;
      }
    }
    if (byIndex != null) {
      if (allowNonStreamable || byIndex.isStreamable) return byIndex;
    }
    final hint = fileNameHint?.trim();
    if (hint == null || hint.isEmpty) return null;
    final want = p.basename(hint).toLowerCase();
    if (want.isEmpty) return null;
    for (final f in files) {
      final bn = p.basename(f.name).toLowerCase();
      final full = f.name.toLowerCase().replaceAll('\\', '/');
      if (bn != want && !full.endsWith('/$want')) continue;
      if (!allowNonStreamable && !f.isStreamable) continue;
      return f;
    }
    return null;
  }

  void _disposeTorrentForAudiobookRetry(String hash, String mapKey) {
    _stopAudiobookStreamsForMapKey(mapKey);
    final tid = _activeTorrents.remove(hash);
    if (tid == null) return;
    try {
      LibtorrentFlutter.instance.disposeTorrent(tid);
    } catch (e) {
      _log('Audiobook retry disposeTorrent: $e');
    }
  }

  void _setState(EngineState s) {
    if (_state == s) return;
    _state = s;
    onStateChanged?.call(s);
  }

  void _log(String message) {
    debugPrint('[TorrentStream] $message');
    onLogLine?.call(message);
  }
}
