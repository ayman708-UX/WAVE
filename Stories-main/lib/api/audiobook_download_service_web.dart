import 'package:flutter/foundation.dart';

import 'audiobook_download_types.dart';
import 'audiobook_service.dart';

class AudiobookDownloadService {
  static final AudiobookDownloadService _instance =
      AudiobookDownloadService._internal();
  factory AudiobookDownloadService() => _instance;
  AudiobookDownloadService._internal();

  final ValueNotifier<Map<String, AudiobookDownloadProgress>> activeDownloads =
      ValueNotifier({});

  final ValueNotifier<Set<String>> downloadingChapters = ValueNotifier({});
  final ValueNotifier<Set<String>> downloadedChapterKeys = ValueNotifier({});

  Future<void> downloadBook(
    Audiobook book,
    List<AudiobookChapter> chapters,
  ) async {
    debugPrint('[AudiobookDownload] Web: downloads not supported');
  }

  Future<void> cancelDownload(String audioBookId) async {}

  Future<void> downloadSingleChapter(
    Audiobook book,
    AudiobookChapter chapter,
    int chapterIndex,
  ) async {}

  Future<void> checkDownloadedChapters(String audioBookId, int totalChapters) async {}

  Future<List<DownloadedAudiobook>> getDownloadedBooks() async => [];

  Future<bool> isBookDownloaded(String audioBookId) async => false;

  Future<DownloadedAudiobook?> getDownloadedBook(String audioBookId) async => null;

  Future<void> deleteBook(String audioBookId) async {}

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
}
