import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum EngineState { stopped, starting, ready, error }

class TorrentStreamService {
  TorrentStreamService._internal();
  static final TorrentStreamService instance = TorrentStreamService._internal();

  EngineState _state = EngineState.stopped;
  final Map<String, int> _activeTorrents = {};
  final Map<String, Map<int, int>> _audiobookStreamsByFile = {};
  final Map<String, Map<int, String>> _audiobookStreamUrls = {};
  final Set<int> _disposedTorrentIds = {};
  final Set<int> _disposedStreamIds = {};
  StreamSubscription? _torrentUpdatesSub;
  final Map<int, TorrentInfo> _latestUpdates = {};

  Future<bool> start() async {
    if (_state == EngineState.ready) return true;
    if (_state == EngineState.starting) {
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_state == EngineState.ready) return true;
        if (_state == EngineState.error) return false;
      }
      return false;
    }

    _state = EngineState.starting;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${docDir.path}/torrent_downloads');
      if (!downloadsDir.existsSync()) {
        downloadsDir.createSync(recursive: true);
      }

      await LibtorrentFlutter.init(
        defaultSavePath: downloadsDir.path,
        fetchTrackers: true,
        pollInterval: const Duration(seconds: 1),
      );

      _torrentUpdatesSub = LibtorrentFlutter.instance.torrentUpdates.listen((updates) {
        _latestUpdates.addAll(updates);
      });
      _state = EngineState.ready;
      debugPrint('[TorrentStream] Engine ready (libtorrent_flutter)');
      return true;
    } catch (e, st) {
      debugPrint('[TorrentStream] Failed to start engine: $e\n$st');
      _state = EngineState.error;
      return false;
    }
  }

  Future<List<FileInfo>> getTorrentAudioFiles(String magnet) async {
    try {
      final ready = await start();
      if (!ready) return [];

      final infoHash = _extractHash(magnet);
      if (infoHash == null) return [];

      int? torrentId = _activeTorrents[infoHash];
      if (torrentId == null) {
        torrentId = LibtorrentFlutter.instance.addMagnet(magnet, null, false);
        _activeTorrents[infoHash] = torrentId;
      }

      final files = await _waitForMetadata(torrentId, timeout: const Duration(seconds: 12));
      if (files == null || files.isEmpty) return [];

      final constExts = {'.mp3', '.m4b', '.m4a', '.aac', '.flac', '.ogg', '.opus', '.wav', '.wma'};
      final audioFiles = <FileInfo>[];
      for (final f in files) {
        final name = f.path.split('/').last.split('\\').last;
        final lower = name.toLowerCase();
        if (constExts.any((ext) => lower.endsWith(ext))) {
          audioFiles.add(f);
        }
      }
      return audioFiles;
    } catch (e) {
      debugPrint('[TorrentStream] getTorrentAudioFiles error: $e');
      return [];
    }
  }

  static final _hashRegExp = RegExp(r'[0-9a-fA-F]{40}');
  String? _extractHash(String magnetOrHash) {
    final btih = RegExp(r'btih:([0-9a-fA-F]{40})', caseSensitive: false)
        .firstMatch(magnetOrHash);
    if (btih != null) return btih.group(1)!.toLowerCase();
    final match = _hashRegExp.firstMatch(magnetOrHash);
    return match?.group(0)?.toLowerCase();
  }

  Future<List<FileInfo>?> _waitForMetadata(int torrentId, {Duration timeout = const Duration(seconds: 30)}) async {
    final completer = Completer<List<FileInfo>?>();
    StreamSubscription? sub;
    var polls = 0;

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        debugPrint('[TorrentStream] Metadata timeout');
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

  FileInfo? _resolveAudiobookFileInfo(List<FileInfo> files, int fileIdx) {
    for (final f in files) {
      if (f.index == fileIdx) {
        return f;
      }
    }
    return null;
  }

  void _safeStopStream(int streamId) {
    if (_disposedStreamIds.contains(streamId)) return;
    _disposedStreamIds.add(streamId);
    try {
      LibtorrentFlutter.instance.stopStream(streamId);
    } catch (e) {
      debugPrint('[TorrentStream] Stop stream error: $e');
    }
  }

  void _safeDisposeTorrent(int torrentId) {
    if (_disposedTorrentIds.contains(torrentId)) return;
    _disposedTorrentIds.add(torrentId);
    try {
      LibtorrentFlutter.instance.disposeTorrent(torrentId);
    } catch (e) {
      debugPrint('[TorrentStream] Dispose torrent error: $e');
    }
  }

  void _stopAudiobookStreamsForMapKey(String mapKey) {
    final byFile = _audiobookStreamsByFile.remove(mapKey);
    _audiobookStreamUrls.remove(mapKey);
    if (byFile == null) return;
    for (final streamId in byFile.values) {
      _safeStopStream(streamId);
    }
  }

  void _disposeTorrentForAudiobookRetry(String hash, String mapKey) {
    _stopAudiobookStreamsForMapKey(mapKey);
    final tid = _activeTorrents.remove(hash);
    if (tid == null) return;
    _safeDisposeTorrent(tid);
  }

  Future<String?> getStreamUrl(String magnetLink, int fileIdx) async {
    if (_state != EngineState.ready) {
      final started = await start();
      if (!started) return null;
    }

    final hash = _extractHash(magnetLink);
    final key = hash ?? magnetLink;
    final saveToRam = false;
    final maxCacheBytes = 0;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        late final int torrentId;
        if (hash != null && _activeTorrents.containsKey(hash)) {
          torrentId = _activeTorrents[hash]!;
        } else {
          torrentId = LibtorrentFlutter.instance.addMagnet(magnetLink, null, saveToRam);
          if (hash != null) {
            _activeTorrents[hash] = torrentId;
          }
          final metaFiles = await _waitForMetadata(torrentId);
          if (metaFiles == null || metaFiles.isEmpty) {
            _safeDisposeTorrent(torrentId);
            if (hash != null) _activeTorrents.remove(hash);
            return null;
          }
        }

        final files = LibtorrentFlutter.instance.getFiles(torrentId);
        if (files.isEmpty) {
          if (attempt == 0 && hash != null) {
            _disposeTorrentForAudiobookRetry(hash, key);
            continue;
          }
          return null;
        }

        final fi = _resolveAudiobookFileInfo(files, fileIdx);
        if (fi == null) return null;

        final streamIdx = fi.index;

        _stopAudiobookStreamsForMapKey(key);

        final byFile = _audiobookStreamsByFile.putIfAbsent(key, () => {});

        try {
          final streamInfo = LibtorrentFlutter.instance.startStream(
            torrentId,
            fileIndex: streamIdx,
            maxCacheBytes: maxCacheBytes,
          );
          byFile[streamIdx] = streamInfo.id;
          var streamUrl = streamInfo.url;
          try {
            // Give MPV a format hint via the URL path
            final ext = (fi as dynamic).path ?? (fi as dynamic).name ?? 'audio.mp3';
            streamUrl += '/' + Uri.encodeComponent(ext.split('/').last);
          } catch (_) {}
          _audiobookStreamUrls.putIfAbsent(key, () => {})[streamIdx] = streamUrl;
          return streamUrl;
        } catch (e) {
          debugPrint('[TorrentStream] startStream failed: $e');
          if (attempt == 0 && hash != null) {
            _disposeTorrentForAudiobookRetry(hash, key);
            continue;
          }
          return null;
        }
      } catch (e) {
        debugPrint('[TorrentStream] error: $e');
        if (attempt == 0 && hash != null) {
          _disposeTorrentForAudiobookRetry(hash, key);
          continue;
        }
        return null;
      }
    }
    return null;
  }

  Future<void> removeTorrent(String magnetOrHash) async {
    final hash = _extractHash(magnetOrHash);
    final key = hash ?? magnetOrHash;

    _stopAudiobookStreamsForMapKey(key);

    if (_activeTorrents.containsKey(key)) {
      final torrentId = _activeTorrents[key]!;
      _safeDisposeTorrent(torrentId);
      _activeTorrents.remove(key);
      _latestUpdates.remove(torrentId);
    }
  }
}
