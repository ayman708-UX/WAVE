import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';
import '../api/models/deezer_playlist.dart';
import '../api/models/deezer_track.dart';
import '../api/models/deezer_user.dart';
import '../api/models/deezer_artist.dart';
import '../api/models/deezer_album.dart';

final supabasePlaylistSyncProvider = Provider<SupabasePlaylistSync>((ref) {
  return SupabasePlaylistSync();
});

/// Handles syncing local playlists to Supabase so they appear on profiles
/// and in the community playlists section.
class SupabasePlaylistSync {
  final _client = Supabase.instance.client;

  bool get _isSignedIn => _client.auth.currentUser != null;
  String? get _userId => _client.auth.currentUser?.id;

  // Mutex lock to prevent race conditions when creating and adding tracks simultaneously
  final Set<String> _syncingPlaylists = {};

  /// Create or update a playlist in Supabase.
  Future<String?> syncPlaylist({
    required DeezerPlaylist playlist,
    required List<DeezerTrack> tracks,
    required bool isPublic,
    String? oldTitle,
  }) async {
    if (!_isSignedIn) return null;

    final lookupTitle = oldTitle ?? playlist.title;

    // Wait if this playlist is currently syncing
    while (_syncingPlaylists.contains(lookupTitle) || _syncingPlaylists.contains(playlist.title)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _syncingPlaylists.add(lookupTitle);
    if (playlist.title != lookupTitle) {
      _syncingPlaylists.add(playlist.title);
    }

    try {
      // Convert tracks to a JSON-friendly list using full DeezerTrack JSON
      final songsJson = tracks.map((t) => t.toJson()).toList();

      // Check if this playlist already exists in Supabase
      final existingResponse = await _client
          .from('playlists')
          .select('id')
          .eq('user_id', _userId!)
          .eq('name', lookupTitle)
          .limit(1);
          
      final existing = existingResponse.isNotEmpty ? existingResponse.first : null;

      if (existing != null) {
        // Update existing
        await _client.from('playlists').update({
          'name': playlist.title,
          'description': playlist.description,
          'is_public': isPublic,
          'songs': songsJson,
        }).eq('id', existing['id']);
        appLogger.i('Playlist synced (updated): ${playlist.title}');
        return existing['id'] as String;
      } else {
        // Insert new
        final result = await _client.from('playlists').insert({
          'user_id': _userId,
          'name': playlist.title,
          'description': playlist.description,
          'is_public': isPublic,
          'songs': songsJson,
        }).select('id').single();
        appLogger.i('Playlist synced (created): ${playlist.title}');
        return result['id'] as String;
      }
    } catch (e) {
      appLogger.e('Failed to sync playlist: $e');
      return null;
    } finally {
      _syncingPlaylists.remove(lookupTitle);
      _syncingPlaylists.remove(playlist.title);
    }
  }

  /// Delete a playlist from Supabase by name (since local IDs don't match).
  Future<void> deletePlaylist(String playlistName) async {
    if (!_isSignedIn) return;
    try {
      await _client
          .from('playlists')
          .delete()
          .eq('user_id', _userId!)
          .eq('name', playlistName);
    } catch (e) {
      appLogger.e('Failed to delete playlist from Supabase: $e');
    }
  }

  /// Sync all local playlists to Supabase at once.
  Future<void> syncAllPlaylists({
    required List<DeezerPlaylist> playlists,
    required Map<int, List<DeezerTrack>> trackMap,
  }) async {
    if (!_isSignedIn || playlists.isEmpty) return;
    
    try {
      // 1. Fetch existing playlists in Supabase to avoid duplicates
      final existingResponse = await _client
          .from('playlists')
          .select('name')
          .eq('user_id', _userId!);
      
      final existingNames = existingResponse.map((row) => row['name'].toString()).toSet();
      
      // 2. Filter local playlists that don't exist remotely
      final playlistsToInsert = playlists.where((pl) => !existingNames.contains(pl.title)).toList();
      
      if (playlistsToInsert.isEmpty) return;

      // 3. Prepare rows for bulk insert
      final rows = playlistsToInsert.map((pl) {
        final tracks = trackMap[pl.id] ?? [];
        final songsJson = tracks.map((t) => {
          'id': t.id,
          'title': t.title,
          'artist': t.artist?.name ?? 'Unknown',
          'cover_url': t.album?.coverMedium ?? t.album?.cover ?? '',
          'duration': t.duration,
        }).toList();

        return {
          'user_id': _userId,
          'name': pl.title,
          'description': pl.description,
          'is_public': pl.public ?? true,
          'songs': songsJson,
        };
      }).toList();

      // 4. Bulk insert
      await _client.from('playlists').insert(rows);
      appLogger.i('Bulk synced ${rows.length} playlists to Supabase.');
    } catch (e) {
      appLogger.e('Failed to bulk sync playlists: $e');
    }
  }

  /// Download all user playlists from Supabase to restore local library.
  Future<void> downloadPlaylists({
    required Function(DeezerPlaylist playlist, List<DeezerTrack> tracks) onPlaylistFound,
  }) async {
    if (!_isSignedIn) return;

    try {
      final response = await _client
          .from('playlists')
          .select()
          .eq('user_id', _userId!);

      for (final row in response) {
        final name = row['name'] ?? 'Untitled';
        final description = row['description'] ?? '';
        final isPublic = row['is_public'] ?? true;
        final songs = row['songs'] as List<dynamic>? ?? [];

        String? pictureUrl;
        if (songs.isNotEmpty) {
          final firstSong = songs.first as Map<String, dynamic>;
          final album = firstSong['album'] as Map<String, dynamic>?;
          pictureUrl = album?['cover_medium']?.toString() ?? album?['cover']?.toString();
        }

        final playlist = DeezerPlaylist(
          id: -(row['id'].hashCode.abs()), // Generate a guaranteed negative unique local ID based on Supabase row ID
          title: name,
          description: description,
          public: isPublic,
          nbTracks: songs.length,
          picture: pictureUrl,
          creator: const DeezerUser(id: 0, name: 'You'),
        );

        final parsedTracks = <DeezerTrack>[];
        for (final s in songs) {
          try {
            parsedTracks.add(DeezerTrack.fromJson(s as Map<String, dynamic>));
          } catch (e) {
            appLogger.w('Skipping legacy or corrupted playlist track: $e');
          }
        }

        onPlaylistFound(playlist, parsedTracks);
      }
    } catch (e) {
      appLogger.e('Failed to download playlists from Supabase: $e');
    }
  }
}
