import 'package:path/path.dart' as p;

import 'audiobook_service.dart';

class AudiobookDownloadProgress {
  final String audioBookId;
  final Audiobook book;
  final int totalChapters;
  final int completedChapters;
  final String status;
  final String? error;

  AudiobookDownloadProgress({
    required this.audioBookId,
    required this.book,
    required this.totalChapters,
    required this.completedChapters,
    required this.status,
    this.error,
  });

  double get progress =>
      totalChapters > 0 ? completedChapters / totalChapters : 0;
}

class DownloadedAudiobook {
  final Audiobook book;
  final List<DownloadedChapter> chapters;
  final String coverPath;
  final int totalSizeBytes;
  final DateTime downloadedAt;

  DownloadedAudiobook({
    required this.book,
    required this.chapters,
    required this.coverPath,
    required this.totalSizeBytes,
    required this.downloadedAt,
  });

  factory DownloadedAudiobook.fromJson(Map<String, dynamic> json, String basePath) {
    return DownloadedAudiobook(
      book: Audiobook.fromJson(json['book']),
      chapters: (json['chapters'] as List)
          .map((c) => DownloadedChapter.fromJson(c, basePath))
          .toList(),
      coverPath: p.join(basePath, json['coverFile'] ?? 'cover.jpg'),
      totalSizeBytes: json['totalSizeBytes'] ?? 0,
      downloadedAt: DateTime.fromMillisecondsSinceEpoch(json['downloadedAt'] ?? 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'book': book.toJson(),
      'chapters': chapters.map((c) => c.toJson()).toList(),
      'coverFile': p.basename(coverPath),
      'totalSizeBytes': totalSizeBytes,
      'downloadedAt': downloadedAt.millisecondsSinceEpoch,
    };
  }
}

class DownloadedChapter {
  final String title;
  final String filePath;
  final int sizeBytes;

  DownloadedChapter({
    required this.title,
    required this.filePath,
    required this.sizeBytes,
  });

  factory DownloadedChapter.fromJson(Map<String, dynamic> json, String basePath) {
    return DownloadedChapter(
      title: json['title'] ?? '',
      filePath: p.join(basePath, json['file'] ?? ''),
      sizeBytes: json['sizeBytes'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'file': p.basename(filePath),
      'sizeBytes': sizeBytes,
    };
  }
}
