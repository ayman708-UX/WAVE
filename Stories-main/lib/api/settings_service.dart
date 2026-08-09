import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audiobook_prefs_keys.dart';

String _audiobookEntryId(String raw) {
  try {
    final m = json.decode(raw) as Map<String, dynamic>;
    final b = m['book'];
    if (b is Map) return (b['audioBookId'] as String?) ?? '';
  } catch (_) {}
  return '';
}

int _audiobookHistoryTs(String raw) {
  try {
    return (json.decode(raw) as Map)['timestamp'] as int? ?? 0;
  } catch (_) {
    return 0;
  }
}

int _audiobookHistoryChapter(String raw) {
  try {
    return ((json.decode(raw) as Map)['chapterIndex'] as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
}

int _audiobookHistoryPositionMs(String raw) {
  try {
    return ((json.decode(raw) as Map)['positionMs'] as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
}

String _pickBetterHistoryEntry(String a, String b) {
  final chA = _audiobookHistoryChapter(a);
  final chB = _audiobookHistoryChapter(b);
  final posA = _audiobookHistoryPositionMs(a);
  final posB = _audiobookHistoryPositionMs(b);
  final tsA = _audiobookHistoryTs(a);
  final tsB = _audiobookHistoryTs(b);

  if (chA == chB) {
    if (posB > 60_000 && posA < 5000) return b;
    if (posA > 60_000 && posB < 5000) return a;
    if (posA != posB) return posA > posB ? a : b;
  }
  return tsA >= tsB ? a : b;
}

int _audiobookBookmarkTs(String raw) {
  try {
    final m = json.decode(raw) as Map;
    return (m['savedAt'] as num?)?.toInt() ??
        (m['timestamp'] as num?)?.toInt() ??
        0;
  } catch (_) {
    return 0;
  }
}

List<String> mergeAudiobookHistoryLists(List<String> local, List<String> remote) {
  final map = <String, String>{};
  void ingest(String x) {
    final id = _audiobookEntryId(x);
    if (id.isEmpty) return;
    final prev = map[id];
    if (prev == null) {
      map[id] = x;
    } else {
      map[id] = _pickBetterHistoryEntry(prev, x);
    }
  }

  for (final x in remote) {
    ingest(x);
  }
  for (final x in local) {
    ingest(x);
  }
  final out = map.values.toList()
    ..sort((a, b) => _audiobookHistoryTs(b).compareTo(_audiobookHistoryTs(a)));
  if (out.length > 10) return out.sublist(0, 10);
  return out;
}

List<String> mergeAudiobookBookmarkLists(
  List<String> local,
  List<String> remote, {
  int localUpdatedAt = 0,
}) {
  if (remote.isEmpty) return List<String>.from(local);

  var remoteMax = 0;
  for (final x in remote) {
    final ts = _audiobookBookmarkTs(x);
    if (ts > remoteMax) remoteMax = ts;
  }

  // Local deletes and edits stay authoritative until another device writes newer data.
  if (localUpdatedAt >= remoteMax) {
    return List<String>.from(local);
  }

  final map = <String, String>{};
  void ingest(String x) {
    final id = _audiobookEntryId(x);
    if (id.isEmpty) return;
    final prev = map[id];
    if (prev == null || _audiobookBookmarkTs(x) >= _audiobookBookmarkTs(prev)) {
      map[id] = x;
    }
  }

  for (final x in remote) {
    ingest(x);
  }
  for (final x in local) {
    ingest(x);
  }

  final out = map.values.toList()
    ..sort((a, b) => _audiobookBookmarkTs(b).compareTo(_audiobookBookmarkTs(a)));
  return out;
}

List<String> mergeAudiobookLikedLists(List<String> local, List<String> remote) {
  final map = <String, String>{};
  for (final x in remote) {
    final id = _audiobookEntryId(x);
    if (id.isNotEmpty) map[id] = x;
  }
  for (final x in local) {
    final id = _audiobookEntryId(x);
    if (id.isNotEmpty) map[id] = x;
  }
  return map.values.toList();
}

/// Minimal settings for the standalone Stories app.
class SettingsService {
  SettingsService();

  static final ValueNotifier<int> audiobookPrefsChangeNotifier =
      ValueNotifier<int>(0);

  static void notifyAudiobookPrefsChanged() {
    audiobookPrefsChangeNotifier.value++;
  }

  static const _torrentCacheTypeKey = 'torrent_cache_type';
  static const _torrentRamCacheMbKey = 'torrent_ram_cache_mb';
  static const _playbackSpeedKey = 'audiobook_playback_speed';
  static const _ptCloudSettingsSyncKey = 'pt_cloud_sync_settings';
  static const _userAvatarKey = 'stories_user_avatar';

  static final ValueNotifier<int> userAvatarChangeNotifier = ValueNotifier<int>(0);

  static void notifyUserAvatarChanged() {
    userAvatarChangeNotifier.value++;
  }

  /// Standalone app uses a single profile row in Supabase.
  Future<int> getPlaytorrioProfileId() async => 1;

  Future<bool> isPlaytorrioCloudSettingsSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ptCloudSettingsSyncKey) ?? true;
  }

  Future<void> setPlaytorrioCloudSettingsSyncEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ptCloudSettingsSyncKey, v);
  }

  Future<String> getTorrentCacheType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_torrentCacheTypeKey) ?? 'ram';
  }

  Future<void> setTorrentCacheType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_torrentCacheTypeKey, type);
  }

  Future<int> getTorrentRamCacheMb() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_torrentRamCacheMbKey) ?? 200;
  }

  Future<void> setTorrentRamCacheMb(int mb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_torrentRamCacheMbKey, mb);
  }

  Future<double> getPlaybackSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_playbackSpeedKey) ?? 1.0;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_playbackSpeedKey, speed);
  }

  Future<int> getUserAvatarIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userAvatarKey) ?? 0;
  }

  Future<void> setUserAvatarIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userAvatarKey, index);
    notifyUserAvatarChanged();
  }

  /// Audiobook prefs mirrored to Supabase when signed in.
  Future<Map<String, dynamic>> exportForCloudSync() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      AudiobookPrefsKeys.history:
          prefs.getStringList(AudiobookPrefsKeys.history) ?? [],
      AudiobookPrefsKeys.liked:
          prefs.getStringList(AudiobookPrefsKeys.liked) ?? [],
      AudiobookPrefsKeys.bookmarks:
          prefs.getStringList(AudiobookPrefsKeys.bookmarks) ?? [],
      AudiobookPrefsKeys.bookmarksUpdatedAt:
          prefs.getInt(AudiobookPrefsKeys.bookmarksUpdatedAt) ?? 0,
      _torrentCacheTypeKey: await getTorrentCacheType(),
      _torrentRamCacheMbKey: await getTorrentRamCacheMb(),
      _playbackSpeedKey: await getPlaybackSpeed(),
      _userAvatarKey: await getUserAvatarIndex(),
    };
  }

  Future<void> applyCloudPreferenceMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    for (final e in map.entries) {
      final k = e.key;
      final v = e.value;
      if (k == AudiobookPrefsKeys.history && v is List) {
        final local = prefs.getStringList(AudiobookPrefsKeys.history) ?? [];
        final remote = v.map((x) => x.toString()).toList();
        await prefs.setStringList(
          AudiobookPrefsKeys.history,
          mergeAudiobookHistoryLists(local, remote),
        );
        notifyAudiobookPrefsChanged();
        continue;
      }
      if (k == AudiobookPrefsKeys.liked && v is List) {
        final local = prefs.getStringList(AudiobookPrefsKeys.liked) ?? [];
        final remote = v.map((x) => x.toString()).toList();
        await prefs.setStringList(
          AudiobookPrefsKeys.liked,
          mergeAudiobookLikedLists(local, remote),
        );
        notifyAudiobookPrefsChanged();
        continue;
      }
      if (k == AudiobookPrefsKeys.bookmarks && v is List) {
        final local = prefs.getStringList(AudiobookPrefsKeys.bookmarks) ?? [];
        final remote = v.map((x) => x.toString()).toList();
        final localUpdated =
            prefs.getInt(AudiobookPrefsKeys.bookmarksUpdatedAt) ?? 0;
        final merged = mergeAudiobookBookmarkLists(
          local,
          remote,
          localUpdatedAt: localUpdated,
        );
        await prefs.setStringList(AudiobookPrefsKeys.bookmarks, merged);
        var remoteMax = 0;
        for (final row in remote) {
          final ts = _audiobookBookmarkTs(row);
          if (ts > remoteMax) remoteMax = ts;
        }
        if (remoteMax > localUpdated) {
          await prefs.setInt(AudiobookPrefsKeys.bookmarksUpdatedAt, remoteMax);
        }
        notifyAudiobookPrefsChanged();
        continue;
      }
      if (k == AudiobookPrefsKeys.bookmarksUpdatedAt) {
        final n = v is int ? v : int.tryParse(v.toString());
        if (n != null) {
          await prefs.setInt(AudiobookPrefsKeys.bookmarksUpdatedAt, n);
        }
        continue;
      }
      if (k == _torrentCacheTypeKey && v is String) {
        await setTorrentCacheType(v);
        continue;
      }
      if (k == _torrentRamCacheMbKey) {
        final n = v is int ? v : int.tryParse(v.toString());
        if (n != null) await setTorrentRamCacheMb(n);
        continue;
      }
      if (k == _playbackSpeedKey) {
        final n = v is num ? v.toDouble() : double.tryParse(v.toString());
        if (n != null) await setPlaybackSpeed(n);
        continue;
      }
      if (k == _userAvatarKey) {
        final n = v is int ? v : int.tryParse(v.toString());
        if (n != null) await setUserAvatarIndex(n);
      }
    }
  }
}
