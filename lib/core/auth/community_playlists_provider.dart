import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api/models/community_playlist.dart';
import '../api/models/deezer_playlist.dart';
import '../api/models/deezer_track.dart';
import '../api/models/deezer_artist.dart';
import '../api/models/deezer_album.dart';
import '../utils/app_logger.dart';

final recentCommunityPlaylistsProvider = FutureProvider<List<CommunityPlaylist>>((
  ref,
) async {
  try {
    final client = Supabase.instance.client;
    // We want the most recent public playlists, max 1 per user for variety
    final response = await client
        .from('playlists')
        .select(
          'id, user_id, name, description, is_public, songs, created_at, profiles(username, display_name)',
        )
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
      final creatorName =
          profile?['display_name'] ?? profile?['username'] ?? 'Unknown User';

      final songsList = row['songs'] as List<dynamic>? ?? [];
      final parsedTracks = <DeezerTrack>[];
      for (final s in songsList) {
        if (s is! Map) continue;
        final song = Map<String, dynamic>.from(s as Map);

        final artistJson = song['artist'];
        DeezerArtist? artist;
        if (artistJson is Map) {
          final am = Map<String, dynamic>.from(artistJson);
          artist = DeezerArtist(
            id: int.tryParse(am['id']?.toString() ?? '0') ?? 0,
            name: am['name']?.toString() ?? 'Unknown',
            picture: am['picture']?.toString(),
            pictureSmall: am['picture_small']?.toString(),
            pictureMedium: am['picture_medium']?.toString(),
            pictureBig: am['picture_big']?.toString(),
            pictureXl: am['picture_xl']?.toString(),
          );
        } else if (artistJson is String) {
          artist = DeezerArtist(id: 0, name: artistJson);
        }

        final albumJson = song['album'];
        DeezerAlbum? album;
        if (albumJson is Map) {
          final alm = Map<String, dynamic>.from(albumJson);
          album = DeezerAlbum(
            id: int.tryParse(alm['id']?.toString() ?? '0') ?? 0,
            title: alm['title']?.toString() ?? '',
            cover: alm['cover']?.toString(),
            coverSmall: alm['cover_small']?.toString(),
            coverMedium: alm['cover_medium']?.toString(),
            coverBig: alm['cover_big']?.toString(),
            coverXl: alm['cover_xl']?.toString(),
          );
        } else {
          final coverUrl = song['cover_url']?.toString();
          if (coverUrl != null && coverUrl.isNotEmpty) {
            album = DeezerAlbum(
              id: 0,
              title: '',
              cover: coverUrl,
              coverSmall: coverUrl,
              coverMedium: coverUrl,
              coverBig: coverUrl,
              coverXl: coverUrl,
            );
          }
        }

        parsedTracks.add(
          DeezerTrack(
            id: int.tryParse(song['id']?.toString() ?? '0') ?? 0,
            title: song['title']?.toString() ?? 'Unknown',
            duration: int.tryParse(song['duration']?.toString() ?? '0') ?? 0,
            artist: artist,
            album: album,
          ),
        );
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

      results.add(
        CommunityPlaylist(
          id: playlistIdStr,
          userId: userId,
          creatorName: creatorName,
          playlist: deezerPlaylist,
          tracks: parsedTracks,
          createdAt: DateTime.parse(row['created_at']),
        ),
      );

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

final searchCommunityPlaylistsProvider =
    FutureProvider.family<List<CommunityPlaylist>, String>((ref, query) async {
      if (query.trim().isEmpty) return [];

      try {
        final client = Supabase.instance.client;
        final response = await client
            .from('playlists')
            .select(
              'id, user_id, name, description, is_public, songs, created_at, profiles(username, display_name)',
            )
            .eq('is_public', true)
            .ilike('name', '%$query%')
            .order('created_at', ascending: false)
            .limit(20);

        final results = <CommunityPlaylist>[];

        for (final row in response) {
          final userId = row['user_id'] as String;
          final profile = row['profiles'] as Map<String, dynamic>?;
          final creatorName =
              profile?['display_name'] ??
              profile?['username'] ??
              'Unknown User';

          final songsList = row['songs'] as List<dynamic>? ?? [];
          final parsedTracks = <DeezerTrack>[];
          for (final s in songsList) {
            if (s is! Map) continue;
            final song = Map<String, dynamic>.from(s as Map);

            final artistJson = song['artist'];
            DeezerArtist? artist;
            if (artistJson is Map) {
              final am = Map<String, dynamic>.from(artistJson);
              artist = DeezerArtist(
                id: int.tryParse(am['id']?.toString() ?? '0') ?? 0,
                name: am['name']?.toString() ?? 'Unknown',
                picture: am['picture']?.toString(),
                pictureSmall: am['picture_small']?.toString(),
                pictureMedium: am['picture_medium']?.toString(),
                pictureBig: am['picture_big']?.toString(),
                pictureXl: am['picture_xl']?.toString(),
              );
            } else if (artistJson is String) {
              artist = DeezerArtist(id: 0, name: artistJson);
            }

            final albumJson = song['album'];
            DeezerAlbum? album;
            if (albumJson is Map) {
              final alm = Map<String, dynamic>.from(albumJson);
              album = DeezerAlbum(
                id: int.tryParse(alm['id']?.toString() ?? '0') ?? 0,
                title: alm['title']?.toString() ?? '',
                cover: alm['cover']?.toString(),
                coverSmall: alm['cover_small']?.toString(),
                coverMedium: alm['cover_medium']?.toString(),
                coverBig: alm['cover_big']?.toString(),
                coverXl: alm['cover_xl']?.toString(),
              );
            } else {
              final coverUrl = song['cover_url']?.toString();
              if (coverUrl != null && coverUrl.isNotEmpty) {
                album = DeezerAlbum(
                  id: 0,
                  title: '',
                  cover: coverUrl,
                  coverSmall: coverUrl,
                  coverMedium: coverUrl,
                  coverBig: coverUrl,
                  coverXl: coverUrl,
                );
              }
            }

            parsedTracks.add(
              DeezerTrack(
                id: int.tryParse(song['id']?.toString() ?? '0') ?? 0,
                title: song['title']?.toString() ?? 'Unknown',
                duration:
                    int.tryParse(song['duration']?.toString() ?? '0') ?? 0,
                artist: artist,
                album: album,
              ),
            );
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

          results.add(
            CommunityPlaylist(
              id: playlistIdStr,
              userId: userId,
              creatorName: creatorName,
              playlist: deezerPlaylist,
              tracks: parsedTracks,
              createdAt: DateTime.parse(row['created_at']),
            ),
          );
        }

        return results;
      } catch (e) {
        appLogger.e('Failed to search community playlists: $e');
        return [];
      }
    });
