class Audiobook {
  final String uuid; // Unique ID representing the book
  final String audioBookId; // Original ID from the source
  final String dynamicSlugId;
  final String title;
  final String coverImage;
  final String source; // The scraper source (e.g. 'audionest', 'goldenaudiobooks')
  final String pageUrl; // Direct URL to the book page or magnet URI

  Audiobook({
    required this.uuid,
    required this.audioBookId,
    required this.dynamicSlugId,
    required this.title,
    required this.coverImage,
    required this.source,
    required this.pageUrl,
  });

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'audioBookId': audioBookId,
        'dynamicSlugId': dynamicSlugId,
        'title': title,
        'coverImage': coverImage,
        'source': source,
        'pageUrl': pageUrl,
      };

  factory Audiobook.fromJson(Map<String, dynamic> json) => Audiobook(
        uuid: json['uuid'] ?? '',
        audioBookId: json['audioBookId'] ?? '',
        dynamicSlugId: json['dynamicSlugId'] ?? '',
        title: json['title'] ?? '',
        coverImage: json['coverImage'] ?? '',
        source: json['source'] ?? '',
        pageUrl: json['pageUrl'] ?? '',
      );
}

class AudiobookChapter {
  final String title;
  final String url; // Stream URL, or file path
  final Map<String, String>? httpHeaders; // Required for hotlink bypassing
  final bool isTorrent; // True if this comes from libtorrent
  final int? torrentFileIndex; // Used for libtorrent file prioritization

  AudiobookChapter({
    required this.title,
    required this.url,
    this.httpHeaders,
    this.isTorrent = false,
    this.torrentFileIndex,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'httpHeaders': httpHeaders,
        'isTorrent': isTorrent,
        'torrentFileIndex': torrentFileIndex,
      };

  factory AudiobookChapter.fromJson(Map<String, dynamic> json) => AudiobookChapter(
        title: json['title'] ?? '',
        url: json['url'] ?? '',
        httpHeaders: (json['httpHeaders'] as Map?)?.cast<String, String>(),
        isTorrent: json['isTorrent'] ?? false,
        torrentFileIndex: json['torrentFileIndex'],
      );
}

class AudiobookProgress {
  final Audiobook audiobook;
  final int chapterIndex;
  final int positionSeconds;
  final int updatedAt;

  AudiobookProgress({
    required this.audiobook,
    required this.chapterIndex,
    required this.positionSeconds,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'audiobook': audiobook.toJson(),
        'chapterIndex': chapterIndex,
        'positionSeconds': positionSeconds,
        'updatedAt': updatedAt,
      };

  factory AudiobookProgress.fromJson(Map<String, dynamic> json) {
    int parseTime(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      if (v is String) {
        final numVal = int.tryParse(v);
        if (numVal != null) return numVal;
        final dt = DateTime.tryParse(v);
        if (dt != null) return dt.millisecondsSinceEpoch;
      }
      return 0;
    }

    return AudiobookProgress(
      audiobook: Audiobook.fromJson(
        Map<String, dynamic>.from(json['audiobook'] ?? json['book_data'] ?? {}),
      ),
      chapterIndex: (json['chapterIndex'] ?? json['chapter_index'] as num?)?.toInt() ?? 0,
      positionSeconds: (json['positionSeconds'] ?? json['position_seconds'] as num?)?.toInt() ?? 0,
      updatedAt: parseTime(json['updatedAt'] ?? json['updated_at']),
    );
  }
}
