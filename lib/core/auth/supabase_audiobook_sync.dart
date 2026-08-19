import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/audiobook.dart';
import '../utils/app_logger.dart';

final supabaseAudiobookSyncProvider = Provider<SupabaseAudiobookSync>((ref) {
  return SupabaseAudiobookSync();
});

/// Handles syncing audiobook library items (liked audiobooks) and playback progress to Supabase.
class SupabaseAudiobookSync {
  final _client = Supabase.instance.client;

  bool get _isSignedIn => _client.auth.currentUser != null;
  String? get _userId => _client.auth.currentUser?.id;

  /// Sync a liked/unliked audiobook with Supabase.
  Future<void> syncAudiobook(Audiobook book, {required bool isLiked}) async {
    if (!_isSignedIn) return;
    try {
      if (isLiked) {
        await _client.from('saved_audiobooks').upsert({
          'user_id': _userId,
          'book_id': book.uuid,
          'book_data': book.toJson(),
        }, onConflict: 'user_id,book_id');
      } else {
        await _client
            .from('saved_audiobooks')
            .delete()
            .eq('user_id', _userId!)
            .eq('book_id', book.uuid);
      }
    } catch (e) {
      appLogger.e('Failed to sync audiobook: $e');
    }
  }

  /// Sync audiobook playback progress (chapter + position) with Supabase.
  Future<void> syncProgress(AudiobookProgress progress) async {
    if (!_isSignedIn) return;
    try {
      await _client.from('audiobook_progress').upsert({
        'user_id': _userId,
        'book_id': progress.audiobook.uuid,
        'chapter_index': progress.chapterIndex,
        'position_seconds': progress.positionSeconds,
        'book_data': progress.audiobook.toJson(),
        'updated_at': progress.updatedAt,
      }, onConflict: 'user_id,book_id');
    } catch (e) {
      appLogger.e('Failed to sync audiobook progress: $e');
    }
  }

  /// Delete audiobook progress from Supabase.
  Future<void> removeProgress(String bookUuid) async {
    if (!_isSignedIn) return;
    try {
      await _client
          .from('audiobook_progress')
          .delete()
          .eq('user_id', _userId!)
          .eq('book_id', bookUuid);
    } catch (e) {
      appLogger.e('Failed to delete audiobook progress: $e');
    }
  }

  RealtimeChannel? _realtimeChannel;

  /// Subscribe to real-time changes in audiobook_progress table on Supabase.
  void subscribeToRealtime({required void Function(AudiobookProgress) onUpdate}) {
    if (!_isSignedIn || _userId == null) return;
    try {
      _realtimeChannel?.unsubscribe();
      _realtimeChannel = _client
          .channel('public:audiobook_progress:$_userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'audiobook_progress',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: _userId!,
            ),
            callback: (payload) {
              try {
                final newRecord = payload.newRecord;
                if (newRecord.isNotEmpty) {
                  final progress = AudiobookProgress.fromJson(
                    Map<String, dynamic>.from(newRecord),
                  );
                  onUpdate(progress);
                }
              } catch (e) {
                appLogger.w('Realtime audiobook progress parse error: $e');
              }
            },
          )
          .subscribe();
    } catch (e) {
      appLogger.e('Failed to subscribe to realtime audiobook progress: $e');
    }
  }

  void unsubscribeRealtime() {
    try {
      _realtimeChannel?.unsubscribe();
      _realtimeChannel = null;
    } catch (_) {}
  }

  /// Bulk sync local audiobooks and progress upwards to Supabase.
  Future<void> syncAllAudiobooks({
    required List<Audiobook> books,
    required List<AudiobookProgress> progressList,
  }) async {
    if (!_isSignedIn) return;

    try {
      // Bulk upsert saved audiobooks
      if (books.isNotEmpty) {
        final rows = books
            .map(
              (b) => {
                'user_id': _userId,
                'book_id': b.uuid,
                'book_data': b.toJson(),
              },
            )
            .toList();
        await _client
            .from('saved_audiobooks')
            .upsert(rows, onConflict: 'user_id,book_id');
      }

      // Bulk upsert audiobook progress
      if (progressList.isNotEmpty) {
        final progressRows = progressList
            .map(
              (p) => {
                'user_id': _userId,
                'book_id': p.audiobook.uuid,
                'chapter_index': p.chapterIndex,
                'position_seconds': p.positionSeconds,
                'book_data': p.audiobook.toJson(),
                'updated_at': p.updatedAt,
              },
            )
            .toList();
        await _client
            .from('audiobook_progress')
            .upsert(progressRows, onConflict: 'user_id,book_id');
      }
    } catch (e) {
      appLogger.e('Failed to bulk sync audiobooks to Supabase: $e');
    }
  }

  /// Download user audiobooks & playback progress from Supabase.
  Future<void> downloadAudiobooks({
    required Function(Audiobook) onAudiobookFound,
    required Function(AudiobookProgress) onProgressFound,
  }) async {
    if (!_isSignedIn) return;

    try {
      // Saved audiobooks
      final booksResp = await _client
          .from('saved_audiobooks')
          .select()
          .eq('user_id', _userId!);
      for (final row in booksResp) {
        try {
          final data = row['book_data'] as Map<String, dynamic>;
          final book = Audiobook.fromJson(data);
          onAudiobookFound(book);
        } catch (e) {
          appLogger.w('Skipping corrupted audiobook row: $e');
        }
      }

      // Audiobook progress
      final progressResp = await _client
          .from('audiobook_progress')
          .select()
          .eq('user_id', _userId!);
      for (final row in progressResp) {
        try {
          final progress = AudiobookProgress.fromJson(
            Map<String, dynamic>.from(row),
          );
          onProgressFound(progress);
        } catch (e) {
          appLogger.w('Skipping corrupted audiobook progress row: $e');
        }
      }
    } catch (e) {
      appLogger.e('Failed to download audiobooks from Supabase: $e');
    }
  }
}
