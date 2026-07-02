import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';

import '../api/models/deezer_track.dart';
import '../storage/hive_boxes.dart';

class LocalDownloadMatch {
  const LocalDownloadMatch({
    required this.track,
    required this.localAudioPath,
    required this.exactId,
    required this.score,
  });

  final DeezerTrack track;
  final String? localAudioPath;
  final bool exactId;
  final int score;
}

class LocalDownloadMatcher {
  LocalDownloadMatcher._();

  static bool get _downloadsOpen => Hive.isBoxOpen(HiveBoxes.downloads);

  static bool isDownloadedById(int trackId) {
    return localAudioPathById(trackId) != null;
  }

  static bool isDownloadedTrack(DeezerTrack track) {
    return localAudioPathForTrack(track) != null;
  }

  static String? localAudioPathById(int trackId) {
    if (!_downloadsOpen) return null;
    final box = Hive.box<dynamic>(HiveBoxes.downloads);
    final data = box.get(trackId);
    if (data is! Map) return null;
    final path = Map<String, dynamic>.from(data)['localAudioPath'] as String?;
    if (!_isGoodAudioFile(path)) {
      if (path != null) unawaited(box.delete(trackId));
      return null;
    }
    return path;
  }

  static String? localAudioPathForTrack(DeezerTrack track) {
    return findDownloadedMatch(track, requireAudioPath: true)?.localAudioPath;
  }

  static LocalDownloadMatch? findDownloadedMatch(
    DeezerTrack target, {
    bool requireAudioPath = false,
  }) {
    if (!_downloadsOpen) return null;
    final box = Hive.box<dynamic>(HiveBoxes.downloads);

    final exactData = box.get(target.id);
    if (exactData is Map) {
      final exactMap = Map<String, dynamic>.from(exactData);
      final path = exactMap['localAudioPath'] as String?;
      if (!requireAudioPath || _isGoodAudioFile(path)) {
        final exactTrack = _trackFromMap(exactMap) ?? target;
        return LocalDownloadMatch(
          track: exactTrack,
          localAudioPath: path,
          exactId: true,
          score: 100000,
        );
      }
      if (path != null) unawaited(box.delete(target.id));
    }

    LocalDownloadMatch? best;

    for (final key in box.keys) {
      final data = box.get(key);
      if (data is! Map) continue;

      final map = Map<String, dynamic>.from(data);
      final path = map['localAudioPath'] as String?;
      if (requireAudioPath && !_isGoodAudioFile(path)) {
        if (path != null) unawaited(box.delete(key));
        continue;
      }

      final downloadedTrack = _trackFromMap(map);
      if (downloadedTrack == null) continue;

      final score = scoreTracks(target, downloadedTrack);
      if (score < 2100) continue;

      if (best == null || score > best.score) {
        best = LocalDownloadMatch(
          track: downloadedTrack,
          localAudioPath: path,
          exactId: downloadedTrack.id == target.id,
          score: score,
        );
      }
    }

    return best;
  }

  static LocalDownloadMatch? findDownloadedMatchInList(
    DeezerTrack target,
    List<DeezerTrack> downloadedTracks,
  ) {
    LocalDownloadMatch? best;

    for (final downloadedTrack in downloadedTracks) {
      final score = scoreTracks(target, downloadedTrack);
      if (score < 2100) continue;

      if (best == null || score > best.score) {
        best = LocalDownloadMatch(
          track: downloadedTrack,
          localAudioPath: null,
          exactId: downloadedTrack.id == target.id,
          score: score,
        );
      }
    }

    return best;
  }

  static int scoreTracks(DeezerTrack target, DeezerTrack downloaded) {
    if (target.id == downloaded.id) return 100000;

    final targetTitle = _normalise(target.titleShort ?? target.title);
    final downloadedTitle =
        _normalise(downloaded.titleShort ?? downloaded.title);
    final targetArtist = _normalise(target.artist?.name ?? '');
    final downloadedArtist = _normalise(downloaded.artist?.name ?? '');

    if (targetTitle.isEmpty || downloadedTitle.isEmpty) return 0;

    final titleScore = _textScore(targetTitle, downloadedTitle);
    final artistScore = targetArtist.isEmpty || downloadedArtist.isEmpty
        ? 0
        : _textScore(targetArtist, downloadedArtist);

    if (artistScore < 450 && targetArtist.isNotEmpty) return 0;
    if (titleScore < 900) return 0;

    var score = titleScore + artistScore;

    final td = target.duration;
    final dd = downloaded.duration;
    if (td != null && dd != null && td > 0 && dd > 0) {
      final diff = (td - dd).abs();
      if (diff <= 3) {
        score += 500;
      } else if (diff <= 8) {
        score += 250;
      } else if (diff > 30) {
        score -= 600;
      }
    }

    final targetVersion = _normalise(target.titleVersion ?? '');
    final downloadedVersion = _normalise(downloaded.titleVersion ?? '');
    if (targetVersion.isNotEmpty &&
        downloadedVersion.isNotEmpty &&
        targetVersion == downloadedVersion) {
      score += 120;
    }

    return score;
  }

  static DeezerTrack? _trackFromMap(Map<String, dynamic> map) {
    try {
      final deep = jsonDecode(jsonEncode(map)) as Map<String, dynamic>;
      return DeezerTrack.fromJson(deep);
    } catch (_) {
      return null;
    }
  }

  static bool _isGoodAudioFile(String? path) {
    if (path == null || path.trim().isEmpty) return false;
    try {
      final file = File(path);
      return file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  static int _textScore(String a, String b) {
    if (a == b) return 1600;
    if (a.contains(b) || b.contains(a)) return 1250;

    final aWords = a.split(' ').where((w) => w.isNotEmpty).toSet();
    final bWords = b.split(' ').where((w) => w.isNotEmpty).toSet();
    if (aWords.isEmpty || bWords.isEmpty) return 0;

    final shared = aWords.intersection(bWords).length;
    final maxWords = aWords.length > bWords.length ? aWords.length : bWords.length;
    final overlap = shared / maxWords;

    var score = (overlap * 1000).round();

    if (a.length >= 5 && b.length >= 5) {
      final distance = _levenshtein(a, b);
      final maxLen = a.length > b.length ? a.length : b.length;
      final similarity = 1 - (distance / maxLen);
      if (similarity >= 0.84) {
        score += 500;
      } else if (similarity >= 0.74) {
        score += 250;
      }
    }

    return score;
  }

  static String _normalise(String value) {
    var out = value.toLowerCase();

    out = out
        .replaceAll(RegExp(r'\b(remaster(ed)?|radio edit|single version|album version|explicit|clean|official|audio|video|lyrics?|hd|hq)\b'), ' ')
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return out;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);

    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = <int>[
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      for (var j = 0; j < previous.length; j++) {
        previous[j] = current[j];
      }
    }

    return previous[b.length];
  }
}
