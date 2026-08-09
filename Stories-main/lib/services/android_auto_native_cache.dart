import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists Android Auto browse nodes for the native MediaBrowser fallback.
///
/// When Android Auto connects before Flutter finishes [AudioService.init], the
/// patched audio_service plugin reads these entries synchronously from
/// `FlutterSharedPreferences`.
abstract final class AndroidAutoNativeCache {
  static const _prefsKey = 'stories_aa_browse_v1';

  static Future<void> saveBrowseTree({
    required List<MediaItem> root,
    required List<MediaItem> recent,
    required List<MediaItem> continueListening,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'root': root.map(_itemToJson).toList(),
        'recent': recent.map(_itemToJson).toList(),
        'continue': continueListening.map(_itemToJson).toList(),
      };
      await prefs.setString(_prefsKey, jsonEncode(payload));
    } catch (e, st) {
      debugPrint('AndroidAutoNativeCache: save failed: $e\n$st');
    }
  }

  static Map<String, dynamic> _itemToJson(MediaItem item) => {
        'id': item.id,
        'title': item.title,
        'album': item.album,
        'playable': item.playable,
      };
}
