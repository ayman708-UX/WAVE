import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../api/models/deezer_track.dart';
import '../audio/youtube_stream_resolver.dart';
import '../storage/hive_boxes.dart';
import '../utils/app_logger.dart';
import '../utils/youtube_stream_http.dart';

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  return DownloadManager(ref);
});

final activeDownloadsProvider =
    NotifierProvider<ActiveDownloadsNotifier, Map<int, double>>(
      ActiveDownloadsNotifier.new,
    );

class ActiveDownloadsNotifier extends Notifier<Map<int, double>> {
  @override
  Map<int, double> build() => {};

  void setProgress(int trackId, double progress) {
    state = {...state, trackId: progress};
  }

  void remove(int trackId) {
    final current = Map<int, double>.from(state);
    current.remove(trackId);
    state = current;
  }
}

class DownloadManager {
  DownloadManager(this._ref);

  final Ref _ref;
  final Dio _dio = Dio();
  final YoutubeStreamResolver _resolver = YoutubeStreamResolver();

  Box<dynamic> get _box => Hive.box<dynamic>(HiveBoxes.downloads);

  Future<String> _getAppDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final waveDir = Directory(p.join(dir.path, 'WAVE_Downloads'));
    if (!await waveDir.exists()) {
      await waveDir.create(recursive: true);
    }
    return waveDir.path;
  }

  Future<void> downloadTrack(DeezerTrack track) async {
    final trackId = track.id;
    if (isDownloaded(trackId)) return;

    _setDownloadProgress(trackId, 0.01);

    try {
      final baseDir = await _getAppDir();

      final audioFile = File(p.join(baseDir, '$trackId.webm'));

      var downloadedAudio = false;

      // 1. Download through the same resolved URL/header path used by playback.
      final res = await _resolver.resolveUrl(track);
      if (res != null) {
        try {
          await _dio.download(
            res.url,
            audioFile.path,
            options: Options(
              headers: YoutubeStreamHttp.streamHeaders(
                res.url,
                userAgent: res.userAgent,
              ),
            ),
            onReceiveProgress: (received, total) {
              if (total > 0) {
                _setDownloadProgress(trackId, received / total);
              }
            },
          );
          downloadedAudio = true;
        } catch (e) {
          appLogger.w('Direct download failed for $trackId', error: e);
          if (await audioFile.exists()) {
            await audioFile.delete();
          }
        }
      }

      if (!downloadedAudio) {
        // 2. Last-resort package downloader for stream types not exposed as a
        // direct URL by the custom resolver.
        final streamInfo = await _resolver.resolveStreamInfo(track);
        if (streamInfo == null) {
          throw Exception('Could not resolve audio stream for download');
        }

        final totalBytes = streamInfo.size.totalBytes;
        int receivedBytes = 0;

        final stream = _resolver.yt.videos.streamsClient.get(streamInfo);
        final fileStream = audioFile.openWrite();

        try {
          await for (final chunk in stream) {
            fileStream.add(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              _setDownloadProgress(trackId, receivedBytes / totalBytes);
            }
          }
        } finally {
          await fileStream.flush();
          await fileStream.close();
        }
      }

      // 3. Download cover image (if available).
      final coverUrl =
          track.album?.coverXl ??
          track.album?.coverBig ??
          track.album?.coverMedium ??
          track.album?.cover;
      String? localCoverPath;

      if (coverUrl != null && coverUrl.isNotEmpty) {
        final ext = p.extension(Uri.parse(coverUrl).path);
        final extString = ext.isEmpty ? '.jpg' : ext;
        final coverFile = File(p.join(baseDir, '${trackId}_cover$extString'));

        try {
          await _dio.download(coverUrl, coverFile.path);
          localCoverPath = coverFile.path;
        } catch (e) {
          appLogger.w('Failed to download cover art for $trackId', error: e);
          // Non-fatal, continue with download success
        }
      }

      // 4. Save metadata to Hive
      final metadata =
          jsonDecode(jsonEncode(track.toJson())) as Map<String, dynamic>;
      metadata['localAudioPath'] = audioFile.path;
      if (localCoverPath != null) {
        metadata['localCoverPath'] = localCoverPath;
      }

      await _box.put(trackId, metadata);
      appLogger.i('Successfully downloaded track $trackId');
    } catch (e, st) {
      appLogger.e(
        'Failed to download track $trackId',
        error: e,
        stackTrace: st,
      );
    } finally {
      _removeActiveDownload(trackId);
    }
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

  bool isDownloaded(int trackId) {
    return _box.containsKey(trackId);
  }

  void _setDownloadProgress(int trackId, double progress) {
    _ref.read(activeDownloadsProvider.notifier).setProgress(trackId, progress);
  }

  void _removeActiveDownload(int trackId) {
    _ref.read(activeDownloadsProvider.notifier).remove(trackId);
  }
}
