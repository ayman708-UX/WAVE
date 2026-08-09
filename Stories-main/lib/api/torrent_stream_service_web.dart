import 'dart:async';

import 'package:flutter/foundation.dart';

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

enum EngineState { stopped, starting, ready, error }

/// Web stub: magnet / BitTorrent streaming is not available in the browser.
class TorrentStreamService {
  static final TorrentStreamService _instance = TorrentStreamService._internal();
  factory TorrentStreamService() => _instance;
  TorrentStreamService._internal();

  EngineState _state = EngineState.stopped;
  EngineState get state => _state;

  void Function(EngineState state)? onStateChanged;
  void Function(String line)? onLogLine;

  Future<bool> start() async {
    _setState(EngineState.error);
    debugPrint('[TorrentStream] Web: torrent engine unavailable');
    return false;
  }

  Future<String?> streamTorrent(
    String magnetLink, {
    int? season,
    int? episode,
    int? fileIdx,
  }) async =>
      null;

  Future<String?> streamAudiobookFile(
    String magnetLink,
    int fileIdx, {
    bool allowNonStreamable = false,
    bool stopSiblingStreams = true,
    String? fileNameHint,
  }) async =>
      null;

  Future<bool> prefetchAudiobookMagnet(String magnetLink) async => false;

  Future<String?> prefetchAudiobookChapter(
    String magnetLink,
    int fileIdx, {
    String? fileNameHint,
  }) async =>
      null;

  void stopAudiobookStreamsForMagnet(String magnetLink) {}

  void releaseAudiobookMagnet(String magnetLink) {}

  void removeTorrent(String magnetOrHash) {}

  void disposeOrphanTorrent(int torrentId) {}

  TorrentStats? getTorrentStats(String magnetOrHash) => null;

  Stream<TorrentStats> statsStream(
    String magnetOrHash, {
    Duration interval = const Duration(seconds: 1),
  }) =>
      const Stream.empty();

  Future<void> stop() async {}

  Future<void> cleanup() async {
    await stop();
    _setState(EngineState.stopped);
  }

  void _setState(EngineState s) {
    if (_state == s) return;
    _state = s;
    onStateChanged?.call(s);
  }
}
