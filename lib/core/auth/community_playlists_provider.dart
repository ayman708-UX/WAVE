import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api/models/community_playlist.dart';
import '../api/models/deezer_playlist.dart';
import '../api/models/deezer_track.dart';
import '../utils/app_logger.dart';

final recentCommunityPlaylistsProvider = FutureProvider<List<CommunityPlaylist>>((ref) async {
  try {
    final client = Supabase.instance.client;
    // We want the most recent public playlists, max 1 per user for variety
    final response = await client
        .from('playlists')
        .select('id, user_id, name, description, is_public, songs, created_at, profiles(username, display_name)')
        .eq('is_public', true)
        .order('created_at', ascending: false)
        .limit(50); // Fetch a chunk so we can filter down

    final results = <CommunityPlaylist>[];
    final seenUsers = <String>{};

    for (final row in response) {
      final userId = row['user_id'] as String;
      
      // Enforce 1 playlist per user for the home page
      if (seenUsers.contains(userId)) continue;
      
      final profile = row['profiles'] as Map<String, dynamic>?;
      final creatorName = profile?['display_name'] ?? profile?['username'] ?? 'Unknown User';
      
      final songsList = row['songs'] as List<dynamic>? ?? [];
      final parsedTracks = <DeezerTrack>[];
      for (final s in songsList) {
        try {
          parsedTracks.add(DeezerTrack.fromJson(s as Map<String, dynamic>));
        } catch (e) {
          appLogger.w('Skipping corrupted track in community playlist: $e');
        }
      }

      String? pictureUrl;
      if (parsedTracks.isNotEmpty) {
        final album = parsedTracks.first.album;
        pictureUrl = album?.coverMedium ?? album?.cover;
      }

      final playlistIdStr = row['id'] as String;
      
      final deezerPlaylist = DeezerPlaylist(
        id: -playlistIdStr.hashCode.abs(), // Local pseudo-id
        title: row['name'] ?? 'Untitled',
        description: row['description'] ?? '',
        public: row['is_public'] ?? true,
        nbTracks: parsedTracks.length,
        picture: pictureUrl,
      );

      results.add(CommunityPlaylist(
        id: playlistIdStr,
        userId: userId,
        creatorName: creatorName,
        playlist: deezerPlaylist,
        tracks: parsedTracks,
        createdAt: DateTime.parse(row['created_at']),
      ));

      seenUsers.add(userId);

      // Stop once we have enough for the home page
      if (results.length >= 10) break;
    }

    // Shuffle the results to provide variety from time to time, as requested
    results.shuffle();
    
    return results;
  } catch (e) {
    appLogger.e('Failed to fetch community playlists: $e');
    return [];
  }
});

final searchCommunityPlaylistsProvider = FutureProvider.family<List<CommunityPlaylist>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];

  try {
    final client = Supabase.instance.client;
    final response = await client
        .from('playlists')
        .select('id, user_id, name, description, is_public, songs, created_at, profiles(username, display_name)')
        .eq('is_public', true)
        .ilike('name', '%$query%')
        .order('created_at', ascending: false)
        .limit(20);

    final results = <CommunityPlaylist>[];

    for (final row in response) {
      final userId = row['user_id'] as String;
      final profile = row['profiles'] as Map<String, dynamic>?;
      final creatorName = profile?['display_name'] ?? profile?['username'] ?? 'Unknown User';
      
      final songsList = row['songs'] as List<dynamic>? ?? [];
      final parsedTracks = <DeezerTrack>[];
      for (final s in songsList) {
        try {
          parsedTracks.add(DeezerTrack.fromJson(s as Map<String, dynamic>));
        } catch (_) {}
      }

      String? pictureUrl;
      if (parsedTracks.isNotEmpty) {
        final album = parsedTracks.first.album;
        pictureUrl = album?.coverMedium ?? album?.cover;
      }

      final playlistIdStr = row['id'] as String;
      
      final deezerPlaylist = DeezerPlaylist(
        id: -playlistIdStr.hashCode.abs(),
        title: row['name'] ?? 'Untitled',
        description: row['description'] ?? '',
        public: row['is_public'] ?? true,
        nbTracks: parsedTracks.length,
        picture: pictureUrl,
      );

      results.add(CommunityPlaylist(
        id: playlistIdStr,
        userId: userId,
        creatorName: creatorName,
        playlist: deezerPlaylist,
        tracks: parsedTracks,
        createdAt: DateTime.parse(row['created_at']),
      ));
    }

    return results;
  } catch (e) {
    appLogger.e('Failed to search community playlists: $e');
    return [];
  }
});
