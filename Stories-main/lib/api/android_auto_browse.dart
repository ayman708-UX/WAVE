import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import 'android_auto_ids.dart';
import '../services/android_auto_native_cache.dart';
import 'audiobook_player_service.dart';
import 'audiobook_service.dart';

/// Media browse tree and playback entry points for Android Auto.
abstract final class AndroidAutoBrowse {
  static final _childrenChanged = BehaviorSubject<void>.seeded(null);
  static List<MediaItem>? _cachedRoot;
  static List<MediaItem>? _cachedRecent;

  /// Preload browse nodes so Android Auto gets a fast first response.
  static Future<void> warmCache() => _refreshCache();

  /// Call after listening history changes so Android Auto refreshes its tree.
  static void invalidateCache() {
    _cachedRoot = null;
    _cachedRecent = null;
    _childrenChanged.add(null);
    unawaited(_refreshCache());
  }

  static ValueStream<Map<String, dynamic>> subscribeToChildren(
    String parentMediaId,
  ) {
    return _childrenChanged
        .map((_) => <String, dynamic>{})
        .shareValueSeeded(<String, dynamic>{});
  }

  static Future<List<MediaItem>> childrenFor(String parentMediaId) async {
    if (parentMediaId == AudioService.recentRootId) {
      _cachedRecent ??= await _recentChildren();
      return _cachedRecent!;
    }
    if (parentMediaId == AudioService.browsableRootId) {
      _cachedRoot ??= await _rootChildren();
      return _cachedRoot!;
    }
    if (parentMediaId == AndroidAutoIds.continueParentId) {
      return _continueListeningChildren();
    }
    if (parentMediaId == AndroidAutoIds.nowPlayingParentId) {
      return _nowPlayingChapterChildren();
    }
    return const [];
  }

  static Future<void> _refreshCache() async {
    try {
      _cachedRoot = await _rootChildren();
      _cachedRecent = await _recentChildren();
      final continueItems = await _continueListeningChildren();
      await AndroidAutoNativeCache.saveBrowseTree(
        root: _cachedRoot!,
        recent: _cachedRecent!,
        continueListening: continueItems,
      );
    } catch (e, st) {
      debugPrint('AndroidAutoBrowse: cache refresh failed: $e\n$st');
    }
  }

  static Future<List<MediaItem>> _rootChildren() async {
    final items = <MediaItem>[];
    final history = await AudiobookPlayerService().getHistory();
    if (history.isNotEmpty) {
      items.add(_folder(
        id: AndroidAutoIds.continueParentId,
        title: 'Continue listening',
        subtitle: '${history.length} titles',
      ));
    }

    final book = AudiobookPlayerService().currentBook.value;
    final chapters = AudiobookPlayerService().currentChapterCount;
    if (book != null && chapters > 0) {
      items.add(_folder(
        id: AndroidAutoIds.nowPlayingParentId,
        title: book.title,
        subtitle: 'Chapters',
        artUri: _artUriForBook(book),
      ));
    }

    if (items.isEmpty) {
      items.add(const MediaItem(
        id: 'stories_empty',
        title: 'Open Stories on your phone',
        album: 'Stories',
        playable: false,
      ));
    }
    return items;
  }

  static Future<List<MediaItem>> _recentChildren() async {
    final history = await AudiobookPlayerService().getHistory();
    if (history.isEmpty) return const [];

    final progress = history.first;
    final rawBook = progress['book'];
    if (rawBook is! Map) return const [];

    try {
      final book = Audiobook.fromJson(Map<String, dynamic>.from(rawBook));
      final ciRaw = progress['chapterIndex'];
      final chapterIndex = ciRaw is int
          ? ciRaw
          : (ciRaw is num ? ciRaw.toInt() : int.tryParse('$ciRaw') ?? 0);
      return [
        MediaItem(
          id: AndroidAutoIds.resume(book.audioBookId),
          album: 'Continue listening',
          title: book.title,
          artist: 'Chapter ${chapterIndex + 1}',
          artUri: _artUriForBook(book),
          playable: true,
        ),
      ];
    } catch (e) {
      debugPrint('AndroidAutoBrowse: recent item failed: $e');
      return const [];
    }
  }

  static Future<List<MediaItem>> _continueListeningChildren() async {
    final history = await AudiobookPlayerService().getHistory();
    final items = <MediaItem>[];
    for (final progress in history) {
      final rawBook = progress['book'];
      if (rawBook is! Map) continue;
      try {
        final book = Audiobook.fromJson(Map<String, dynamic>.from(rawBook));
        final ciRaw = progress['chapterIndex'];
        final chapterIndex = ciRaw is int
            ? ciRaw
            : (ciRaw is num ? ciRaw.toInt() : int.tryParse('$ciRaw') ?? 0);
        items.add(MediaItem(
          id: AndroidAutoIds.resume(book.audioBookId),
          album: 'Continue listening',
          title: book.title,
          artist: 'Chapter ${chapterIndex + 1}',
          artUri: _artUriForBook(book),
          playable: true,
        ));
      } catch (e) {
        debugPrint('AndroidAutoBrowse: skip history row: $e');
      }
    }
    return items;
  }

  static Future<List<MediaItem>> _nowPlayingChapterChildren() async {
    final player = AudiobookPlayerService();
    final book = player.currentBook.value;
    if (book == null) return const [];

    final chapters = player.currentChapters;
    return List<MediaItem>.generate(chapters.length, (index) {
      final chapter = chapters[index];
      return MediaItem(
        id: AndroidAutoIds.chapter(book.audioBookId, index),
        album: book.title,
        title: chapter.title.isEmpty ? 'Chapter ${index + 1}' : chapter.title,
        artist: 'Stories',
        artUri: _artUriForBook(book),
        playable: true,
      );
    });
  }

  static MediaItem _folder({
    required String id,
    required String title,
    String? subtitle,
    Uri? artUri,
  }) {
    return MediaItem(
      id: id,
      title: title,
      album: subtitle ?? 'Stories',
      artUri: artUri,
      playable: false,
      extras: const {
        AndroidContentStyle.browsableHintKey:
            AndroidContentStyle.listItemHintValue,
      },
    );
  }

  static Uri? _artUriForBook(Audiobook book) {
    var art = book.thumbUrl.trim();
    if (art.isEmpty) art = book.coverImage.trim();
    return art.isEmpty ? null : Uri.tryParse(art);
  }

  static Future<void> playMediaId(String mediaId) async {
    if (mediaId.startsWith(AndroidAutoIds.resumePrefix)) {
      final audioBookId = mediaId.substring(AndroidAutoIds.resumePrefix.length);
      await AudiobookPlayerService().resumeFromAndroidAuto(audioBookId);
      return;
    }

    if (mediaId.startsWith(AndroidAutoIds.chapterPrefix)) {
      final payload = mediaId.substring(AndroidAutoIds.chapterPrefix.length);
      final sep = payload.lastIndexOf('_');
      if (sep <= 0) return;
      final audioBookId = payload.substring(0, sep);
      final index = int.tryParse(payload.substring(sep + 1));
      if (index == null) return;
      await AudiobookPlayerService()
          .playChapterFromAndroidAuto(audioBookId, index);
    }
  }
}
