import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../api/models/deezer_track.dart';
import '../audio/youtube_stream_resolver.dart';
import '../audio/youtube_rate_limit_guard.dart';
import '../storage/hive_boxes.dart';
import '../utils/app_logger.dart';
import '../utils/youtube_stream_http.dart';
import 'local_download_matcher.dart';

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  return DownloadManager(ref);
});

final activeDownloadsProvider =
    NotifierProvider<ActiveDownloadsNotifier, Map<int, double>>(
  ActiveDownloadsNotifier.new,
);

final downloadQueueProvider =
    NotifierProvider<DownloadQueueNotifier, DownloadQueueState>(
  DownloadQueueNotifier.new,
);

final downloadLocationProvider = FutureProvider<String>((ref) async {
  return ref.read(downloadManagerProvider).downloadsDirectory();
});

class DownloadExportTarget {
  const DownloadExportTarget({
    required this.privatePath,
    required this.exportPath,
    required this.label,
    required this.isPublicBackup,
  });

  final String privatePath;
  final String exportPath;
  final String label;
  final bool isPublicBackup;
}

class DownloadExportResult {
  const DownloadExportResult({
    required this.privatePath,
    required this.exportPath,
    required this.filesCopied,
    required this.bytesCopied,
    required this.metadataItems,
  });

  final String privatePath;
  final String exportPath;
  final int filesCopied;
  final int bytesCopied;
  final int metadataItems;
}

class ActiveDownloadsNotifier extends Notifier<Map<int, double>> {
  @override
  Map<int, double> build() => {};

  void setProgress(int trackId, double progress) {
    state = {...state, trackId: progress.clamp(0.0, 1.0)};
  }

  void remove(int trackId) {
    final current = Map<int, double>.from(state);
    current.remove(trackId);
    state = current;
  }
}

enum DownloadItemStatus {
  waiting,
  resolving,
  downloading,
  done,
  skipped,
  failed,
  cancelled,
}

extension DownloadItemStatusLabel on DownloadItemStatus {
  String get label {
    return switch (this) {
      DownloadItemStatus.waiting => 'Waiting',
      DownloadItemStatus.resolving => 'Resolving YouTube stream',
      DownloadItemStatus.downloading => 'Downloading',
      DownloadItemStatus.done => 'Downloaded',
      DownloadItemStatus.skipped => 'Already downloaded',
      DownloadItemStatus.failed => 'Failed',
      DownloadItemStatus.cancelled => 'Cancelled',
    };
  }

  bool get isFinished {
    return this == DownloadItemStatus.done ||
        this == DownloadItemStatus.skipped ||
        this == DownloadItemStatus.failed ||
        this == DownloadItemStatus.cancelled;
  }
}

class DownloadQueueItem {
  const DownloadQueueItem({
    required this.track,
    required this.status,
    required this.progress,
    required this.attempt,
    this.error,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0,
    this.allowFuzzyDownloadedSkip = true,
  });

  final DeezerTrack track;
  final DownloadItemStatus status;
  final double progress;
  final int attempt;
  final String? error;
  final int receivedBytes;
  final int totalBytes;
  final int bytesPerSecond;

  /// Bulk album/playlist downloads may fuzzy-skip similar local tracks.
  /// Manual single-track downloads must use exact Deezer ID only, otherwise
  /// WAVE can wrongly block a specific version from downloading.
  final bool allowFuzzyDownloadedSkip;

  int get trackId => track.id;
  String get title => track.title;
  String get artist => track.artist?.name ?? 'Unknown artist';
  bool get hasBytes => receivedBytes > 0 || totalBytes > 0;

  DownloadQueueItem copyWith({
    DownloadItemStatus? status,
    double? progress,
    int? attempt,
    String? error,
    int? receivedBytes,
    int? totalBytes,
    int? bytesPerSecond,
    bool? allowFuzzyDownloadedSkip,
    bool clearError = false,
  }) {
    return DownloadQueueItem(
      track: track,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      attempt: attempt ?? this.attempt,
      error: clearError ? null : (error ?? this.error),
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      allowFuzzyDownloadedSkip:
          allowFuzzyDownloadedSkip ?? this.allowFuzzyDownloadedSkip,
    );
  }
}

class DownloadQueueState {
  const DownloadQueueState({
    this.running = false,
    this.cancelling = false,
    this.title = 'Download queue',
    this.location,
    this.items = const <DownloadQueueItem>[],
  });

  final bool running;
  final bool cancelling;
  final String title;
  final String? location;
  final List<DownloadQueueItem> items;

  bool get hasItems => items.isNotEmpty;
  int get total => items.length;
  int get downloaded =>
      items.where((i) => i.status == DownloadItemStatus.done).length;
  int get skipped =>
      items.where((i) => i.status == DownloadItemStatus.skipped).length;
  int get failed =>
      items.where((i) => i.status == DownloadItemStatus.failed).length;
  int get cancelled =>
      items.where((i) => i.status == DownloadItemStatus.cancelled).length;
  int get waiting =>
      items.where((i) => i.status == DownloadItemStatus.waiting).length;

  DownloadQueueItem? get current {
    for (final item in items) {
      if (item.status == DownloadItemStatus.resolving ||
          item.status == DownloadItemStatus.downloading) {
        return item;
      }
    }
    return null;
  }

  double get overallProgress {
    if (items.isEmpty) return 0;
    var totalProgress = 0.0;
    for (final item in items) {
      if (item.status == DownloadItemStatus.done ||
          item.status == DownloadItemStatus.skipped ||
          item.status == DownloadItemStatus.failed ||
          item.status == DownloadItemStatus.cancelled) {
        totalProgress += 1;
      } else {
        totalProgress += item.progress.clamp(0.0, 1.0);
      }
    }
    return (totalProgress / items.length).clamp(0.0, 1.0);
  }

  DownloadQueueState copyWith({
    bool? running,
    bool? cancelling,
    String? title,
    String? location,
    List<DownloadQueueItem>? items,
  }) {
    return DownloadQueueState(
      running: running ?? this.running,
      cancelling: cancelling ?? this.cancelling,
      title: title ?? this.title,
      location: location ?? this.location,
      items: items ?? this.items,
    );
  }
}

class DownloadQueueNotifier extends Notifier<DownloadQueueState> {
  @override
  DownloadQueueState build() => const DownloadQueueState();

  void replace(DownloadQueueState next) {
    state = next;
  }
}

class _SlowDownloadException implements Exception {
  const _SlowDownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _DownloadCancelledException implements Exception {
  const _DownloadCancelledException();

  @override
  String toString() => 'Cancelled';
}

class _DownloadHead {
  const _DownloadHead({
    this.contentType,
    this.contentLength = 0,
  });

  final String? contentType;
  final int contentLength;
}

class DownloadManager {
  DownloadManager(this._ref);

  final Ref _ref;
  final Dio _dio = Dio();
  final YoutubeStreamResolver _resolver = YoutubeStreamResolver();

  static const int _slowDownloadBytesPerSecond = 96 * 1024;
  static const Duration _slowDownloadGrace = Duration(seconds: 15);
  static const int _parallelDownloadParts = 3;
  static const int _minimumMultipartBytes = 2 * 1024 * 1024;

  final List<DownloadQueueItem> _queue = <DownloadQueueItem>[];
  bool _processing = false;
  bool _cancelRequested = false;
  CancelToken? _activeCancelToken;
  Completer<void>? _cancelCompleter;
  String _queueTitle = 'Download queue';
  String? _downloadLocation;

  Box<dynamic> get _box => Hive.box<dynamic>(HiveBoxes.downloads);

  Future<String> downloadsDirectory() => _getAppDir();

  Future<DownloadExportTarget> downloadExportTarget() async {
    final privatePath = await _getAppDir();
    final exportPath = await _defaultExportDir();

    return DownloadExportTarget(
      privatePath: privatePath,
      exportPath: exportPath,
      label: _exportLabelForPath(exportPath),
      isPublicBackup: exportPath != privatePath,
    );
  }

  Future<String> _defaultExportDir({String? parentDirectory}) async {
    if (parentDirectory != null && parentDirectory.trim().isNotEmpty) {
      return p.join(parentDirectory, 'WAVE', 'wave_downloads');
    }

    if (Platform.isAndroid) {
      // Best-effort user-visible Android backup path.
      // WAVE still keeps its playable offline files inside app-private storage.
      return p.join(
        '/storage/emulated/0',
        'Download',
        'WAVE',
        'wave_downloads',
      );
    }

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          return p.join(downloads.path, 'WAVE', 'wave_downloads');
        }
      } catch (_) {
        // Fall back below.
      }
    }

    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'WAVE', 'wave_downloads');
  }

  String _exportLabelForPath(String path) {
    if (Platform.isAndroid &&
        path.replaceAll('\\', '/').contains('/Download/WAVE/wave_downloads')) {
      return 'Internal storage/Download/WAVE/wave_downloads';
    }
    return path;
  }

  Future<DownloadExportResult> exportDownloadsBackup({
    String? parentDirectory,
  }) async {
    final privatePath = await _getAppDir();
    final exportPath = await _defaultExportDir(parentDirectory: parentDirectory);

    final sourceDir = Directory(privatePath);
    if (!await sourceDir.exists()) {
      throw Exception('WAVE private download folder was not found.');
    }

    final destDir = Directory(exportPath);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    var filesCopied = 0;
    var bytesCopied = 0;

    await for (final entity in sourceDir.list(recursive: false)) {
      if (entity is! File) continue;

      final name = p.basename(entity.path);
      final lowerName = name.toLowerCase();
      final ext = p.extension(lowerName);

      if (name.endsWith('.part') || name.contains('.part.seg')) {
        continue;
      }

      // Export backup is for songs only. Do not copy downloaded cover artwork
      // or any extra metadata files into the user's public backup folder.
      if (lowerName.contains('_cover') ||
          ext == '.jpg' ||
          ext == '.jpeg' ||
          ext == '.png' ||
          ext == '.webp' ||
          ext == '.gif' ||
          lowerName == 'wave_downloads_manifest.json') {
        continue;
      }

      final target = File(p.join(destDir.path, name));
      await target.parent.create(recursive: true);
      await entity.copy(target.path);

      filesCopied++;
      bytesCopied += await target.length();
    }

    appLogger.i(
      'Exported WAVE song backup to $exportPath '
      '($filesCopied audio files, $bytesCopied bytes)',
    );

    return DownloadExportResult(
      privatePath: privatePath,
      exportPath: exportPath,
      filesCopied: filesCopied,
      bytesCopied: bytesCopied,
      metadataItems: 0,
    );
  }

  Future<void> openExportedDownloadsFolder({String? parentDirectory}) async {
    final dir = await _defaultExportDir(parentDirectory: parentDirectory);

    if (Platform.isWindows) {
      await Process.run('explorer.exe', <String>[dir]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', <String>[dir]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', <String>[dir]);
      return;
    }

    throw UnsupportedError(_exportLabelForPath(dir));
  }

  String? localAudioPathFor(int trackId) {
    final data = _box.get(trackId);
    if (data is! Map) return null;

    final map = Map<String, dynamic>.from(data);
    final audioPath = map['localAudioPath'] as String?;
    if (audioPath == null || audioPath.isEmpty) return null;

    final file = File(audioPath);
    if (!file.existsSync()) return null;
    return audioPath;
  }

  Future<String> _getAppDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final waveDir = Directory(p.join(dir.path, 'WAVE_Downloads'));
    if (!await waveDir.exists()) {
      await waveDir.create(recursive: true);
    }
    return waveDir.path;
  }

  Future<void> openDownloadsFolder() async {
    final dir = await _getAppDir();

    if (Platform.isWindows) {
      await Process.run('explorer.exe', <String>[dir]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', <String>[dir]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', <String>[dir]);
      return;
    }

    final target = await downloadExportTarget();
    throw UnsupportedError(
      'WAVE stores playable downloads privately. Use Export backup to copy them to ${target.label}.',
    );
  }

  Future<void> downloadTrack(DeezerTrack track) async {
    await queueTracks(
      <DeezerTrack>[track],
      title: 'Single track',
      replaceFinishedQueue: !_processing,
      allowFuzzyDownloadedSkip: false,
    );
  }

  Future<void> downloadAlbum(String albumTitle, List<DeezerTrack> tracks) async {
    await queueTracks(
      tracks,
      title: 'Album: $albumTitle',
      replaceFinishedQueue: !_processing,
    );
  }

  Future<void> downloadPlaylist(
    String playlistTitle,
    List<DeezerTrack> tracks,
  ) async {
    await queueTracks(
      tracks,
      title: 'Playlist: $playlistTitle',
      replaceFinishedQueue: !_processing,
    );
  }

  Future<void> queueTracks(
    List<DeezerTrack> tracks, {
    required String title,
    bool replaceFinishedQueue = false,
    bool allowFuzzyDownloadedSkip = true,
  }) async {
    final unique = <int, DeezerTrack>{};
    for (final track in tracks) {
      unique[track.id] = track;
    }

    if (unique.isEmpty) return;

    _downloadLocation ??= await _getAppDir();

    if (replaceFinishedQueue ||
        (!_processing && _queue.every((i) => i.status.isFinished))) {
      _queue.clear();
    }

    _queueTitle = title;
    for (final track in unique.values) {
      final alreadyQueued = _queue.any(
        (item) =>
            item.trackId == track.id &&
            !item.status.isFinished &&
            item.status != DownloadItemStatus.failed,
      );
      if (alreadyQueued) continue;

      final alreadyDownloaded = _isDownloadedForQueue(
        track,
        allowFuzzy: allowFuzzyDownloadedSkip,
      );

      _queue.add(
        DownloadQueueItem(
          track: track,
          status: alreadyDownloaded
              ? DownloadItemStatus.skipped
              : DownloadItemStatus.waiting,
          progress: alreadyDownloaded ? 1.0 : 0.0,
          attempt: 0,
          allowFuzzyDownloadedSkip: allowFuzzyDownloadedSkip,
        ),
      );
    }

    _emitQueue();

    if (!_processing) {
      unawaited(_processQueue());
    }
  }

  void cancelQueue() {
    _cancelRequested = true;
    if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
      _cancelCompleter!.complete();
    }
    _activeCancelToken?.cancel('Cancelled by user');
    for (var i = 0; i < _queue.length; i++) {
      final item = _queue[i];
      if (item.status == DownloadItemStatus.waiting) {
        _queue[i] = item.copyWith(
          status: DownloadItemStatus.cancelled,
          progress: 1.0,
          error: 'Cancelled',
        );
      }
    }
    _emitQueue(cancelling: true);
  }

  Future<void> retryFailed() async {
    var changed = false;
    for (var i = 0; i < _queue.length; i++) {
      final item = _queue[i];
      if (item.status == DownloadItemStatus.failed ||
          item.status == DownloadItemStatus.cancelled) {
        _queue[i] = item.copyWith(
          status: _isDownloadedForQueue(
            item.track,
            allowFuzzy: item.allowFuzzyDownloadedSkip,
          )
              ? DownloadItemStatus.skipped
              : DownloadItemStatus.waiting,
          progress: _isDownloadedForQueue(
            item.track,
            allowFuzzy: item.allowFuzzyDownloadedSkip,
          )
              ? 1.0
              : 0.0,
          attempt: 0,
          clearError: true,
        );
        changed = true;
      }
    }

    if (!changed) return;
    _cancelRequested = false;
    _emitQueue(cancelling: false);

    if (!_processing) {
      unawaited(_processQueue());
    }
  }

  void clearFinishedQueue() {
    _queue.removeWhere((item) => item.status.isFinished);
    _emitQueue(cancelling: false);
  }

  Future<void> _processQueue() async {
    if (_processing) return;

    _processing = true;
    _cancelRequested = false;
    _cancelCompleter = Completer<void>();
    _emitQueue(running: true, cancelling: false);

    try {
      for (var i = 0; i < _queue.length; i++) {
        var item = _queue[i];

        if (_cancelRequested) {
          if (item.status == DownloadItemStatus.waiting) {
            _queue[i] = item.copyWith(
              status: DownloadItemStatus.cancelled,
              progress: 1.0,
              error: 'Cancelled',
            );
          }
          continue;
        }

        if (item.status != DownloadItemStatus.waiting) {
          continue;
        }


        if (_isDownloadedForQueue(
          item.track,
          allowFuzzy: item.allowFuzzyDownloadedSkip,
        )) {
          _queue[i] = item.copyWith(
            status: DownloadItemStatus.skipped,
            progress: 1.0,
            clearError: true,
          );
          _emitQueue();
          continue;
        }

        var success = false;
        Object? lastError;

        _queue[i] = item.copyWith(
          status: DownloadItemStatus.resolving,
          progress: 0.03,
          attempt: 1,
          clearError: true,
        );
        _emitQueue();

        try {
          await _downloadTrackNow(item.track, itemIndex: i);
          success = true;
        } catch (e, st) {
          lastError = e;
          appLogger.w(
            'Download failed for ${item.track.title}',
            error: e,
            stackTrace: st,
          );

          if (e is YoutubeRateLimitException ||
              YoutubeRateLimitGuard.isRateLimitError(e)) {
            _cancelRequested = true;
            _activeCancelToken?.cancel('YouTube rate limit');
          }
        }

        item = _queue[i];

        if (_cancelRequested) {
          _queue[i] = item.copyWith(
            status: DownloadItemStatus.cancelled,
            progress: 1.0,
            error: 'Cancelled',
          );
          _removeActiveDownload(item.trackId);
          _emitQueue();
          continue;
        }

        if (success) {
          _queue[i] = item.copyWith(
            status: DownloadItemStatus.done,
            progress: 1.0,
            clearError: true,
          );
        } else {
          _queue[i] = item.copyWith(
            status: DownloadItemStatus.failed,
            progress: 1.0,
            error: _friendlyError(lastError),
          );
        }

          _removeActiveDownload(item.trackId);
        _emitQueue();
      }
    } finally {
      _processing = false;
      _cancelRequested = false;
      _activeCancelToken = null;
      _cancelCompleter = null;
      _emitQueue(running: false, cancelling: false);
    }
  }

  Future<AudioOnlyStreamInfo?> _streamInfoForDownload(DeezerTrack track) {
    YoutubeRateLimitGuard.throwIfLimited();
    return _cancelable(
      _resolver.resolveStreamInfo(track).timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      ),
    );
  }

  Future<void> _downloadTrackNow(
    DeezerTrack track, {
    required int itemIndex,
  }) async {
    final trackId = track.id;
    _throwIfCancelled();
    _setDownloadProgress(trackId, 0.01);

    final baseDir = await _getAppDir();

    await _deletePartialFiles(baseDir, trackId);

    // v23Q:
    // Download resolving must be quick. Use the same fast playable URL path
    // first, then use the slower streamInfo manifest fallback only if the fast
    // path fails. Do not sit through two long attempts per song.
    final res = await _cancelable(
      _resolver.resolveUrl(track).timeout(
        const Duration(seconds: 16),
        onTimeout: () => null,
      ),
    );

    if (res != null) {
      try {
        _throwIfCancelled();
        await _downloadFromDirectUrl(
          track: track,
          url: res.url,
          userAgent: res.userAgent,
          itemIndex: itemIndex,
          baseDir: baseDir,
        );
        return;
      } catch (e, st) {
        if (_isCancelError(e)) rethrow;
        appLogger.w(
          'Fast direct URL download failed for $trackId; trying streamInfo fallback',
          error: e,
          stackTrace: st,
        );
        await _deletePartialFiles(baseDir, trackId);
      }
    }

    _throwIfCancelled();
    final streamInfo = await _streamInfoForDownload(track);

    if (streamInfo != null) {
      try {
        _throwIfCancelled();
        await _downloadFromStreamInfo(
          track: track,
          streamInfo: streamInfo,
          itemIndex: itemIndex,
          baseDir: baseDir,
        );
        return;
      } catch (e, st) {
        if (_isCancelError(e)) rethrow;
        appLogger.w(
          'streamInfo fallback download failed for $trackId',
          error: e,
          stackTrace: st,
        );
        await _deletePartialFiles(baseDir, trackId);
      }
    }

    throw Exception('Could not find a playable YouTube audio source quickly. Use Retry failed later.');
  }

  Future<void> _downloadFromStreamInfo({
    required DeezerTrack track,
    required AudioOnlyStreamInfo streamInfo,
    required int itemIndex,
    required String baseDir,
  }) async {
    final trackId = track.id;
    final streamUrl = streamInfo.url.toString();
    final totalBytes = streamInfo.size.totalBytes;
    final ext = _extensionFor(url: streamUrl);
    final audioFile = await _targetAudioFile(baseDir, trackId, ext);
    final partFile = File('${audioFile.path}.part');

    _updateQueueItem(
      itemIndex,
      status: DownloadItemStatus.downloading,
      progress: 0.08,
      receivedBytes: 0,
      totalBytes: totalBytes > 0 ? totalBytes : 0,
      bytesPerSecond: 0,
    );

    if (totalBytes >= _minimumMultipartBytes) {
      try {
        await _dioMultipartDownload(
          track: track,
          url: streamUrl,
          userAgent: YoutubeStreamHttp.userAgentForUrl(streamUrl),
          itemIndex: itemIndex,
          partFile: partFile,
          totalBytes: totalBytes,
        );
      } catch (e, st) {
        if (_isCancelError(e)) rethrow;
        appLogger.w(
          'Multipart stream download failed; falling back to single stream',
          error: e,
          stackTrace: st,
        );
        await _deletePartialFiles(baseDir, trackId);
        await _dioFastDownload(
          track: track,
          url: streamUrl,
          userAgent: YoutubeStreamHttp.userAgentForUrl(streamUrl),
          itemIndex: itemIndex,
          partFile: partFile,
          expectedTotalBytes: totalBytes > 0 ? totalBytes : null,
          useRangeHeader: true,
        );
      }
    } else {
      await _dioFastDownload(
        track: track,
        url: streamUrl,
        userAgent: YoutubeStreamHttp.userAgentForUrl(streamUrl),
        itemIndex: itemIndex,
        partFile: partFile,
        expectedTotalBytes: totalBytes > 0 ? totalBytes : null,
        useRangeHeader: true,
      );
    }

    await _finalizeAudioFile(partFile, audioFile);
    await _saveTrackMetadata(
      track: track,
      audioFile: audioFile,
      baseDir: baseDir,
      ext: ext,
    );
  }

  Future<void> _downloadFromDirectUrl({
    required DeezerTrack track,
    required String url,
    required String? userAgent,
    required int itemIndex,
    required String baseDir,
  }) async {
    _updateQueueItem(
      itemIndex,
      status: DownloadItemStatus.downloading,
      progress: 0.08,
      receivedBytes: 0,
      totalBytes: 0,
      bytesPerSecond: 0,
    );

    final headers = YoutubeStreamHttp.streamHeaders(
      url,
      userAgent: userAgent,
      range: 'bytes=0-',
    );

    final head = await _safeHead(url, headers);
    final contentType = head.contentType;
    final totalBytes = head.contentLength;
    final ext = _extensionFor(url: url, contentType: contentType);
    final audioFile = await _targetAudioFile(baseDir, track.id, ext);
    final partFile = File('${audioFile.path}.part');

    if (totalBytes >= _minimumMultipartBytes) {
      try {
        await _dioMultipartDownload(
          track: track,
          url: url,
          userAgent: userAgent,
          itemIndex: itemIndex,
          partFile: partFile,
          totalBytes: totalBytes,
        );
      } catch (e, st) {
        if (_isCancelError(e)) rethrow;
        appLogger.w(
          'Multipart direct download failed; falling back to single direct',
          error: e,
          stackTrace: st,
        );
        await _deletePartialFiles(baseDir, track.id);
        await _dioFastDownload(
          track: track,
          url: url,
          userAgent: userAgent,
          itemIndex: itemIndex,
          partFile: partFile,
          expectedTotalBytes: totalBytes > 0 ? totalBytes : null,
          useRangeHeader: true,
        );
      }
    } else {
      await _dioFastDownload(
        track: track,
        url: url,
        userAgent: userAgent,
        itemIndex: itemIndex,
        partFile: partFile,
        expectedTotalBytes: totalBytes > 0 ? totalBytes : null,
        useRangeHeader: true,
      );
    }

    await _finalizeAudioFile(partFile, audioFile);
    await _saveTrackMetadata(
      track: track,
      audioFile: audioFile,
      baseDir: baseDir,
      ext: ext,
    );
  }

  Future<void> _dioMultipartDownload({
    required DeezerTrack track,
    required String url,
    required String? userAgent,
    required int itemIndex,
    required File partFile,
    required int totalBytes,
  }) async {
    if (totalBytes <= 0) {
      throw Exception('Cannot use multipart download without file size');
    }

    final trackId = track.id;
    final stopwatch = Stopwatch()..start();
    final parts = _buildByteRanges(totalBytes, _parallelDownloadParts);
    final receivedByPart = List<int>.filled(parts.length, 0);
    final segmentFiles = <File>[];
    final cancelToken = CancelToken();
    var cancelledBecauseSlow = false;

    _activeCancelToken = cancelToken;

    try {
      final tasks = <Future<void>>[];

      for (var i = 0; i < parts.length; i++) {
        final range = parts[i];
        final segment = File('${partFile.path}.seg$i');
        segmentFiles.add(segment);

        if (await segment.exists()) {
          await segment.delete();
        }

        final headers = YoutubeStreamHttp.streamHeaders(
          url,
          userAgent: userAgent,
          range: 'bytes=${range.$1}-${range.$2}',
        );

        tasks.add(
          _dio.download(
            url,
            segment.path,
            cancelToken: cancelToken,
            options: Options(
              headers: headers,
              responseType: ResponseType.bytes,
              followRedirects: true,
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 20),
              validateStatus: (code) => code == 206,
            ),
            onReceiveProgress: (received, total) {
              receivedByPart[i] = received;
              final receivedTotal =
                  receivedByPart.fold<int>(0, (sum, value) => sum + value);
              final elapsedMs = stopwatch.elapsedMilliseconds;
              final bytesPerSecond = elapsedMs <= 0
                  ? 0
                  : ((receivedTotal * 1000) / elapsedMs).round();
              final progress =
                  _downloadProgressFromBytes(receivedTotal, totalBytes);

              _setDownloadProgress(trackId, progress);
              _updateQueueItem(
                itemIndex,
                status: DownloadItemStatus.downloading,
                progress: progress,
                receivedBytes: receivedTotal,
                totalBytes: totalBytes,
                bytesPerSecond: bytesPerSecond,
              );

              if (stopwatch.elapsed >= _slowDownloadGrace &&
                  bytesPerSecond > 0 &&
                  bytesPerSecond < _slowDownloadBytesPerSecond &&
                  receivedTotal < 2 * 1024 * 1024) {
                cancelledBecauseSlow = true;
                cancelToken.cancel(
                  'Multipart source throttled at ${_formatSpeed(bytesPerSecond)}',
                );
              }
            },
          ),
        );
      }

      await Future.wait(tasks);

      if (await partFile.exists()) {
        await partFile.delete();
      }

      final sink = partFile.openWrite();
      try {
        for (final segment in segmentFiles) {
          if (!await segment.exists()) {
            throw Exception('Missing downloaded segment ${p.basename(segment.path)}');
          }
          final bytes = await segment.readAsBytes();
          sink.add(bytes);
        }
      } finally {
        await sink.close();
      }

      final finalLength = await partFile.length();
      if (finalLength != totalBytes) {
        throw Exception(
          'Multipart download size mismatch: expected $totalBytes, got $finalLength',
        );
      }
    } catch (e) {
      if (cancelledBecauseSlow) {
        throw _SlowDownloadException(
          'Multipart source too slow (${_formatSpeedFromQueue(itemIndex)}).',
        );
      }
      rethrow;
    } finally {
      stopwatch.stop();
      for (final segment in segmentFiles) {
        try {
          if (await segment.exists()) {
            await segment.delete();
          }
        } catch (_) {}
      }
    }
  }

  List<(int, int)> _buildByteRanges(int totalBytes, int requestedParts) {
    final partCount = requestedParts.clamp(1, 8);
    final partSize = (totalBytes / partCount).ceil();
    final ranges = <(int, int)>[];

    var start = 0;
    while (start < totalBytes) {
      final end = (start + partSize - 1).clamp(0, totalBytes - 1);
      ranges.add((start, end));
      start = end + 1;
    }

    return ranges;
  }

  Future<void> _dioFastDownload({
    required DeezerTrack track,
    required String url,
    required String? userAgent,
    required int itemIndex,
    required File partFile,
    required int? expectedTotalBytes,
    required bool useRangeHeader,
  }) async {
    final trackId = track.id;
    final stopwatch = Stopwatch()..start();
    var cancelledBecauseSlow = false;

    final headers = YoutubeStreamHttp.streamHeaders(
      url,
      userAgent: userAgent,
      range: useRangeHeader ? 'bytes=0-' : null,
    );

    _activeCancelToken = CancelToken();

    try {
      await _dio.download(
        url,
        partFile.path,
        cancelToken: _activeCancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 20),
          validateStatus: (code) =>
              code != null && code >= 200 && code < 400,
        ),
        onReceiveProgress: (received, total) {
          final elapsedMs = stopwatch.elapsedMilliseconds;
          final bytesPerSecond = elapsedMs <= 0
              ? 0
              : ((received * 1000) / elapsedMs).round();
          final effectiveTotal = total > 0
              ? total
              : (expectedTotalBytes != null && expectedTotalBytes > 0
                  ? expectedTotalBytes
                  : 0);
          final progress = _downloadProgressFromBytes(received, effectiveTotal);
          _setDownloadProgress(trackId, progress);
          _updateQueueItem(
            itemIndex,
            status: DownloadItemStatus.downloading,
            progress: progress,
            receivedBytes: received,
            totalBytes: effectiveTotal > 0 ? effectiveTotal : 0,
            bytesPerSecond: bytesPerSecond,
          );

          // If a CDN URL is throttled to tiny speed, do not waste 10 minutes
          // on one song. Abort this source and try the next resolver path.
          if (stopwatch.elapsed >= _slowDownloadGrace &&
              bytesPerSecond > 0 &&
              bytesPerSecond < _slowDownloadBytesPerSecond &&
              received < 2 * 1024 * 1024) {
            cancelledBecauseSlow = true;
            _activeCancelToken?.cancel(
              'Download throttled at ${_formatSpeed(bytesPerSecond)}',
            );
          }
        },
      );
    } catch (e) {
      if (cancelledBecauseSlow) {
        throw _SlowDownloadException(
          'Download source too slow (${_formatSpeedFromQueue(itemIndex)}).',
        );
      }
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }


  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const _DownloadCancelledException();
    }
  }

  Future<T> _cancelable<T>(Future<T> future) async {
    final cancel = _cancelCompleter;
    if (cancel == null) return future;
    return Future.any<T>(<Future<T>>[
      future,
      cancel.future.then<T>((_) => throw const _DownloadCancelledException()),
    ]);
  }

  String _formatSpeedFromQueue(int itemIndex) {
    if (itemIndex < 0 || itemIndex >= _queue.length) return 'slow';
    return _formatSpeed(_queue[itemIndex].bytesPerSecond);
  }

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 KB/s';
    final kb = bytesPerSecond / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 100 ? 1 : 0)} KB/s';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 2 : 1)} MB/s';
  }

  Future<_DownloadHead> _safeHead(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final response = await _dio
          .head<dynamic>(
            url,
            options: Options(
              headers: headers,
              followRedirects: true,
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              validateStatus: (code) => code != null && code < 500,
            ),
          )
          .timeout(const Duration(seconds: 10));

      final contentLength =
          int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '') ??
              0;

      return _DownloadHead(
        contentType: response.headers.value(Headers.contentTypeHeader),
        contentLength: contentLength,
      );
    } catch (e) {
      appLogger.w('Could not HEAD download URL: $e');
      return const _DownloadHead();
    }
  }

  String _extensionFor({required String url, String? contentType}) {
    final type = (contentType ?? '').toLowerCase();

    if (type.contains('audio/mp4') ||
        type.contains('video/mp4') ||
        type.contains('audio/x-m4a') ||
        type.contains('application/mp4')) {
      return '.m4a';
    }
    if (type.contains('audio/webm') || type.contains('video/webm')) {
      return '.webm';
    }
    if (type.contains('audio/ogg') || type.contains('application/ogg')) {
      return '.ogg';
    }
    if (type.contains('audio/mpeg') || type.contains('audio/mp3')) {
      return '.mp3';
    }
    if (type.contains('audio/aac')) {
      return '.aac';
    }

    final uriExt = p.extension(Uri.tryParse(url)?.path ?? '').toLowerCase();
    if (uriExt == '.m4a' || uriExt == '.mp4') return '.m4a';
    if (uriExt == '.webm') return '.webm';
    if (uriExt == '.ogg' || uriExt == '.oga') return '.ogg';
    if (uriExt == '.mp3') return '.mp3';
    if (uriExt == '.aac') return '.aac';

    // YouTube audio-only streams are commonly WebM/Opus when the container is
    // not obvious. MediaKit plays this reliably, but we no longer force every
    // stream to webm when content-type or URL tells us otherwise.
    return '.webm';
  }

  Future<File> _targetAudioFile(String baseDir, int trackId, String ext) async {
    for (final oldExt in const <String>[
      '.webm',
      '.m4a',
      '.mp3',
      '.ogg',
      '.oga',
      '.aac',
      '.mp4',
    ]) {
      final old = File(p.join(baseDir, '$trackId$oldExt'));
      if (await old.exists()) {
        await old.delete();
      }
    }
    return File(p.join(baseDir, '$trackId$ext'));
  }

  Future<void> _finalizeAudioFile(File partFile, File audioFile) async {
    if (!await partFile.exists()) {
      throw Exception('Downloaded temp file was not created');
    }

    final bytes = await partFile.length();
    if (bytes < 1024) {
      await partFile.delete();
      throw Exception('Downloaded file is too small or empty');
    }

    if (await audioFile.exists()) {
      await audioFile.delete();
    }

    await partFile.rename(audioFile.path);
  }

  Future<void> _deletePartialFiles(String baseDir, int trackId) async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('$trackId.') && name.endsWith('.part')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _saveTrackMetadata({
    required DeezerTrack track,
    required File audioFile,
    required String baseDir,
    required String ext,
  }) async {
    _setDownloadProgress(track.id, 0.94);

    final coverUrl =
        track.album?.coverXl ??
        track.album?.coverBig ??
        track.album?.coverMedium ??
        track.album?.cover;

    String? localCoverPath;

    if (coverUrl != null && coverUrl.isNotEmpty) {
      final coverExt = p.extension(Uri.parse(coverUrl).path);
      final coverExtString = coverExt.isEmpty ? '.jpg' : coverExt;
      final coverFile = File(p.join(baseDir, '${track.id}_cover$coverExtString'));

      try {
        await _dio.download(coverUrl, coverFile.path);
        if (await coverFile.exists() && await coverFile.length() > 0) {
          localCoverPath = coverFile.path;
        }
      } catch (e) {
        appLogger.w('Failed to download cover art for ${track.id}', error: e);
      }
    }

    final metadata = jsonDecode(jsonEncode(track.toJson())) as Map<String, dynamic>;
    metadata['localAudioPath'] = audioFile.path;
    metadata['localAudioExt'] = ext;
    metadata['localAudioBytes'] = await audioFile.length();
    metadata['downloadedAt'] = DateTime.now().toIso8601String();
    metadata['downloadSource'] = 'youtube';
    if (localCoverPath != null) {
      metadata['localCoverPath'] = localCoverPath;
    }

    await _box.put(track.id, metadata);
    _setDownloadProgress(track.id, 1.0);
    appLogger.i('Successfully downloaded track ${track.id} to ${audioFile.path}');
  }

  Future<void> deleteDownload(int trackId) async {
    final data = _box.get(trackId);
    if (data == null) return;

    final map = Map<String, dynamic>.from(data as Map);
    final audioPath = map['localAudioPath'] as String?;
    final coverPath = map['localCoverPath'] as String?;

    if (audioPath != null) {
      final f = File(audioPath);
      if (await f.exists()) await f.delete();
    }

    if (coverPath != null) {
      final f = File(coverPath);
      if (await f.exists()) await f.delete();
    }

    await _box.delete(trackId);
  }

  bool _isDownloadedTrack(DeezerTrack track) {
    return LocalDownloadMatcher.localAudioPathForTrack(track) != null;
  }

  bool _isDownloadedForQueue(
    DeezerTrack track, {
    required bool allowFuzzy,
  }) {
    if (allowFuzzy) {
      return _isDownloadedTrack(track);
    }

    return LocalDownloadMatcher.localAudioPathById(track.id) != null;
  }

  bool isDownloaded(int trackId) {
    final data = _box.get(trackId);
    if (data is! Map) return false;

    final map = Map<String, dynamic>.from(data);
    final audioPath = map['localAudioPath'] as String?;
    if (audioPath == null || audioPath.isEmpty) return false;

    final file = File(audioPath);
    if (!file.existsSync()) {
      unawaited(_box.delete(trackId));
      return false;
    }

    return true;
  }

  double _downloadProgressFromBytes(int received, int total) {
    if (total > 0) {
      return (0.10 + ((received / total) * 0.82)).clamp(0.10, 0.92);
    }

    // Many YouTube/CDN streams do not provide a content-length. In that case
    // keep the UI moving using bytes received so it never looks frozen.
    const assumedSongBytes = 8 * 1024 * 1024; // roughly one normal song
    return (0.10 + ((received / assumedSongBytes) * 0.74)).clamp(0.10, 0.88);
  }

  void _setDownloadProgress(int trackId, double progress) {
    _ref.read(activeDownloadsProvider.notifier).setProgress(trackId, progress);
  }

  void _removeActiveDownload(int trackId) {
    _ref.read(activeDownloadsProvider.notifier).remove(trackId);
  }

  void _updateQueueItem(
    int index, {
    DownloadItemStatus? status,
    double? progress,
    int? attempt,
    String? error,
    int? receivedBytes,
    int? totalBytes,
    int? bytesPerSecond,
  }) {
    if (index < 0 || index >= _queue.length) return;
    _queue[index] = _queue[index].copyWith(
      status: status,
      progress: progress,
      attempt: attempt,
      error: error,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      bytesPerSecond: bytesPerSecond,
      clearError: error == null,
    );
    _emitQueue();
  }

  void _emitQueue({
    bool? running,
    bool? cancelling,
  }) {
    _ref.read(downloadQueueProvider.notifier).replace(
          DownloadQueueState(
            running: running ?? _processing,
            cancelling: cancelling ?? _cancelRequested,
            title: _queueTitle,
            location: _downloadLocation,
            items: List<DownloadQueueItem>.unmodifiable(_queue),
          ),
        );
  }

  bool _isCancelError(Object? error) {
    return error is _DownloadCancelledException ||
        (error is DioException && CancelToken.isCancel(error));
  }

  String _friendlyError(Object? error) {
    if (error == null) return 'Unknown error';
    if (_isCancelError(error)) return 'Cancelled';
    final raw = error.toString();
    if (raw.length <= 160) return raw;
    return '${raw.substring(0, 160)}...';
  }
}
