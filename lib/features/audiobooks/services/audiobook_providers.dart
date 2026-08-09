import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../core/models/audiobook.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../core/auth/supabase_audiobook_sync.dart';
import 'audiobook_scraper_service.dart';

Map<String, dynamic> _deepJson(Map<String, dynamic> json) {
  return jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
}

// ---------------------------------------------------------------------------
// Popular Audiobooks (Restored)
// ---------------------------------------------------------------------------

final popularAudiobooksProvider = FutureProvider<List<Audiobook>>((ref) async {
  return []; // Placeholder
});

// ---------------------------------------------------------------------------
// Search Audiobooks (Restored)
// ---------------------------------------------------------------------------

final searchAudiobooksProvider = FutureProvider.family<List<Audiobook>, String>((ref, query) async {
  return AudiobookScraperService.instance.search(query);
});

// ---------------------------------------------------------------------------
// Liked Audiobooks
// ---------------------------------------------------------------------------

class LikedAudiobooksNotifier extends Notifier<List<Audiobook>> {
  @override
  List<Audiobook> build() {
    final box = Hive.box<dynamic>(HiveBoxes.likedAudiobooks);
    return box.values
        .whereType<Map>()
        .map((m) => Audiobook.fromJson(_deepJson(Map<String, dynamic>.from(m))))
        .toList(growable: false);
  }

  bool isLiked(String uuid) => state.any((a) => a.uuid == uuid);

  Future<void> toggle(Audiobook book) async {
    final box = Hive.box<dynamic>(HiveBoxes.likedAudiobooks);
    final currentlyLiked = isLiked(book.uuid);
    if (currentlyLiked) {
      await box.delete(book.uuid);
      state = state.where((a) => a.uuid != book.uuid).toList(growable: false);
      ref.read(supabaseAudiobookSyncProvider).syncAudiobook(book, isLiked: false);
    } else {
      await box.put(book.uuid, _deepJson(book.toJson()));
      state = <Audiobook>[book, ...state];
      ref.read(supabaseAudiobookSyncProvider).syncAudiobook(book, isLiked: true);
    }
  }

  Future<void> remove(String uuid) async {
    final book = state.firstWhere((a) => a.uuid == uuid, orElse: () => Audiobook(uuid: uuid, audioBookId: '', dynamicSlugId: '', title: '', coverImage: '', source: '', pageUrl: ''));
    await Hive.box<dynamic>(HiveBoxes.likedAudiobooks).delete(uuid);
    state = state.where((a) => a.uuid != uuid).toList(growable: false);
    if (book.title.isNotEmpty) {
      ref.read(supabaseAudiobookSyncProvider).syncAudiobook(book, isLiked: false);
    }
  }
}

final likedAudiobooksProvider =
    NotifierProvider<LikedAudiobooksNotifier, List<Audiobook>>(
        LikedAudiobooksNotifier.new);

// ---------------------------------------------------------------------------
// Audiobook Progress
// ---------------------------------------------------------------------------

class AudiobookProgressNotifier extends Notifier<List<AudiobookProgress>> {
  @override
  List<AudiobookProgress> build() {
    final box = Hive.box<dynamic>(HiveBoxes.audiobookProgress);
    return box.values
        .whereType<Map>()
        .map((m) => AudiobookProgress.fromJson(_deepJson(Map<String, dynamic>.from(m))))
        .toList(growable: false);
  }

  AudiobookProgress? getProgress(String uuid) {
    try {
      return state.firstWhere((p) => p.audiobook.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateProgress(Audiobook book, int chapterIndex, int positionSeconds) async {
    if (positionSeconds < 5 && chapterIndex == 0) return; // Ignore trivial start progress

    final box = Hive.box<dynamic>(HiveBoxes.audiobookProgress);
    final progress = AudiobookProgress(
      audiobook: book,
      chapterIndex: chapterIndex,
      positionSeconds: positionSeconds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await box.put(book.uuid, _deepJson(progress.toJson()));
    
    // Update state, moving the updated item to the front
    final newState = state.where((p) => p.audiobook.uuid != book.uuid).toList();
    newState.insert(0, progress);
    state = newState;

    // Sync to Supabase
    ref.read(supabaseAudiobookSyncProvider).syncProgress(progress);
  }

  Future<void> removeProgress(String uuid) async {
    await Hive.box<dynamic>(HiveBoxes.audiobookProgress).delete(uuid);
    state = state.where((p) => p.audiobook.uuid != uuid).toList(growable: false);
    ref.read(supabaseAudiobookSyncProvider).removeProgress(uuid);
  }
}

final audiobookProgressProvider =
    NotifierProvider<AudiobookProgressNotifier, List<AudiobookProgress>>(
        AudiobookProgressNotifier.new);

