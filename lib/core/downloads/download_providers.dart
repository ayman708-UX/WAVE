import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../api/models/deezer_track.dart';
import '../storage/hive_boxes.dart';

class DownloadedTracksNotifier extends Notifier<List<DeezerTrack>> {
  @override
  List<DeezerTrack> build() {
    _box.watch().listen((_) => _load());
    return _getTracks();
  }

  Box<dynamic> get _box => Hive.box<dynamic>(HiveBoxes.downloads);

  List<DeezerTrack> _getTracks() {
    final list = <DeezerTrack>[];
    final brokenKeys = <dynamic>[];

    for (final key in _box.keys) {
      final val = _box.get(key);
      if (val is Map) {
        try {
          final map = Map<String, dynamic>.from(val);
          final localPath = map['localAudioPath'] as String?;

          // Offline-only safety check: if Hive says a song is downloaded but
          // the actual file is gone, do not show it as downloaded.
          if (localPath == null ||
              localPath.isEmpty ||
              !File(localPath).existsSync()) {
            brokenKeys.add(key);
            continue;
          }

          final deepMap = jsonDecode(jsonEncode(map)) as Map<String, dynamic>;
          list.add(DeezerTrack.fromJson(deepMap));
        } catch (_) {}
      }
    }

    for (final key in brokenKeys) {
      _box.delete(key);
    }

    return list;
  }

  void _load() {
    state = _getTracks();
  }
}

final downloadedTracksProvider =
    NotifierProvider<DownloadedTracksNotifier, List<DeezerTrack>>(
      DownloadedTracksNotifier.new,
    );
