import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'hive_boxes.dart';

/// One entry in the recently-played list. `kind` is one of
/// `'track' | 'album' | 'playlist' | 'artist'`.
class RecentEntry {
  const RecentEntry({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.atMillis,
  });

  final String kind;
  final int id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final int atMillis;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'imageUrl': imageUrl,
    'atMillis': atMillis,
  };

  factory RecentEntry.fromJson(Map<String, dynamic> json) => RecentEntry(
    kind: (json['kind'] as String?) ?? 'track',
    id: json['id'] is num
        ? (json['id'] as num).toInt()
        : int.tryParse(json['id']?.toString() ?? '') ?? 0,
    title: (json['title'] as String?) ?? '',
    subtitle: json['subtitle'] as String?,
    imageUrl: json['imageUrl'] as String?,
    atMillis: (json['atMillis'] as num?)?.toInt() ?? 0,
  );
}

/// Reads / writes the recently-played list backed by Hive.
class RecentlyPlayedNotifier extends Notifier<List<RecentEntry>> {
  static const String _key = 'entries';
  static const int _maxEntries = 50;

  @override
  List<RecentEntry> build() {
    final box = Hive.box<dynamic>(HiveBoxes.recentlyPlayed);
    final raw = box.get(_key);
    if (raw is! List) return <RecentEntry>[];
    return raw
        .whereType<Map>()
        .map((m) => RecentEntry.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> push(RecentEntry entry) async {
    final next = <RecentEntry>[
      entry,
      ...state.where((e) => !(e.kind == entry.kind && e.id == entry.id)),
    ];
    if (next.length > _maxEntries) next.removeRange(_maxEntries, next.length);
    state = next;
    final box = Hive.box<dynamic>(HiveBoxes.recentlyPlayed);
    await box.put(_key, next.map((e) => e.toJson()).toList(growable: false));
  }

  Future<void> remove(RecentEntry entry) async {
    final next = state
        .where((e) => !(e.kind == entry.kind && e.id == entry.id))
        .toList();
    state = next;
    final box = Hive.box<dynamic>(HiveBoxes.recentlyPlayed);
    await box.put(_key, next.map((e) => e.toJson()).toList(growable: false));
  }

  Future<void> clear() async {
    state = const <RecentEntry>[];
    final box = Hive.box<dynamic>(HiveBoxes.recentlyPlayed);
    await box.delete(_key);
  }
}

final recentlyPlayedProvider =
    NotifierProvider<RecentlyPlayedNotifier, List<RecentEntry>>(
      RecentlyPlayedNotifier.new,
    );
