class TorrentResult {
  final String name;
  final String magnet;
  final String seeders;
  final String size;
  final String source;

  TorrentResult({
    required this.name,
    required this.magnet,
    required this.seeders,
    required this.size,
    required this.source,
  });

  factory TorrentResult.fromJson(Map<String, dynamic> json) {
    return TorrentResult(
      name: json['name'] ?? 'Unknown',
      magnet: json['magnet'] ?? '',
      seeders: json['seeders']?.toString() ?? '0',
      size: json['size'] ?? 'Unknown',
      source: json['source'] ?? 'Unknown',
    );
  }

  int get seedersCount => int.tryParse(seeders.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  double get sizeInBytes {
    final s = size.toLowerCase();
    final value = double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    if (s.contains('gb')) return value * 1024 * 1024 * 1024;
    if (s.contains('mb')) return value * 1024 * 1024;
    if (s.contains('kb')) return value * 1024;
    return value;
  }

  int get qualityScore {
    final n = name.toLowerCase();
    if (n.contains('2160p') || n.contains('4k')) return 2160;
    if (n.contains('1080p')) return 1080;
    if (n.contains('720p')) return 720;
    if (n.contains('480p')) return 480;
    return 0;
  }
}
