import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

final supabaseProfileProvider = Provider<SupabaseProfileService>((ref) {
  return SupabaseProfileService();
});

/// Provider that fetches the current user's profile from Supabase.
final currentProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;
  final svc = ref.read(supabaseProfileProvider);
  return svc.getProfile(user.id);
});

class SupabaseProfileService {
  final _client = Supabase.instance.client;

  /// Fetch a single profile by user ID.
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      appLogger.e('Failed to fetch profile: $e');
      return null;
    }
  }

  /// Update the current user's profile.
  Future<void> updateProfile({
    String? displayName,
    String? username,
    String? avatarUrl,
    bool? isPublic,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final updates = <String, dynamic>{};
    if (displayName != null) updates['display_name'] = displayName;
    if (username != null) updates['username'] = username;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (isPublic != null) updates['is_public'] = isPublic;

    if (updates.isEmpty) return;

    try {
      await _client.from('profiles').update(updates).eq('id', user.id);
    } catch (e) {
      appLogger.e('Failed to update profile: $e');
      rethrow;
    }
  }

  /// Search for users by display name or username.
  /// Returns a list of profile maps (only public profiles appear, plus exact
  /// username matches for private profiles so they still show up in search).
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    try {
      final response = await _client
          .from('profiles')
          .select()
          .or('username.ilike.%$q%,display_name.ilike.%$q%')
          .limit(25);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      appLogger.e('User search failed: $e');
      return [];
    }
  }

  /// Fetch all public playlists for a given user.
  Future<List<Map<String, dynamic>>> getUserPlaylists(String userId) async {
    try {
      final response = await _client
          .from('playlists')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      appLogger.e('Failed to fetch user playlists: $e');
      return [];
    }
  }

  /// Fetch saved tracks, albums, and artists (library) for a given user.
  Future<Map<String, List<Map<String, dynamic>>>> getUserLibrary(String userId) async {
    try {
      final tracksFuture = _client
          .from('saved_tracks')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      
      final albumsFuture = _client
          .from('saved_albums')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
          
      final artistsFuture = _client
          .from('saved_artists')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final results = await Future.wait([tracksFuture, albumsFuture, artistsFuture]);
      
      return {
        'tracks': List<Map<String, dynamic>>.from(results[0]),
        'albums': List<Map<String, dynamic>>.from(results[1]),
        'artists': List<Map<String, dynamic>>.from(results[2]),
      };
    } catch (e) {
      appLogger.e('Failed to fetch user library: $e');
      return <String, List<Map<String, dynamic>>>{
        'tracks': <Map<String, dynamic>>[],
        'albums': <Map<String, dynamic>>[],
        'artists': <Map<String, dynamic>>[]
      };
    }
  }

  /// Fetch a single playlist by its unique ID (for sharing/deep linking).
  Future<Map<String, dynamic>?> getPlaylistById(String playlistId) async {
    try {
      final response = await _client
          .from('playlists')
          .select('*, profiles!inner(username, display_name, avatar_url)')
          .eq('id', playlistId)
          .maybeSingle();
      return response;
    } catch (e) {
      appLogger.e('Failed to fetch shared playlist: $e');
      return null;
    }
  }

  /// Fetch community playlists (public playlists from all users) for the
  /// home page "Playlists by WAVE Users" section.
  Future<List<Map<String, dynamic>>> getCommunityPlaylists({int limit = 20}) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      var query = _client
          .from('playlists')
          .select('*, profiles!inner(username, display_name, avatar_url)')
          .eq('is_public', true);

      // Exclude the current user's own playlists
      if (currentUserId != null) {
        query = query.neq('user_id', currentUserId);
      }

      // Fetch more than needed so we can filter and shuffle
      final response = await query.order('created_at', ascending: false).limit(50);
      
      final List<Map<String, dynamic>> results = [];
      final Set<String> seenUsers = {};

      for (final row in response) {
        final userId = row['user_id'] as String;
        // Enforce 1 playlist per user
        if (seenUsers.contains(userId)) continue;

        results.add(row);
        seenUsers.add(userId);

        if (results.length >= limit) break;
      }

      // Shuffle so they refresh from time to time
      results.shuffle();
      
      return results;
    } catch (e) {
      appLogger.e('Failed to fetch community playlists: $e');
      return [];
    }
  }

  /// Search community playlists by name
  Future<List<Map<String, dynamic>>> searchCommunityPlaylists(String searchQuery, {int limit = 20}) async {
    try {
      final currentUserId = _client.auth.currentUser?.id;
      var query = _client
          .from('playlists')
          .select('*, profiles!inner(username, display_name, avatar_url)')
          .eq('is_public', true)
          .ilike('name', '%$searchQuery%');

      if (currentUserId != null) {
        query = query.neq('user_id', currentUserId);
      }

      final response = await query.order('created_at', ascending: false).limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      appLogger.e('Failed to search community playlists: $e');
      return [];
    }
  }
}
