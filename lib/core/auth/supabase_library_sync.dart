import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';
import '../api/models/deezer_album.dart';
import '../api/models/deezer_artist.dart';
import '../api/models/deezer_track.dart';
import '../api/models/deezer_playlist.dart';

final supabaseLibrarySyncProvider = Provider<SupabaseLibrarySync>((ref) {
  return SupabaseLibrarySync();
});

/// Handles syncing local library items (liked tracks, albums, artists) to Supabase
class SupabaseLibrarySync {
  final _client = Supabase.instance.client;

  bool get _isSignedIn => _client.auth.currentUser != null;
  String? get _userId => _client.auth.currentUser?.id;

  Future<void> syncTrack(DeezerTrack track, {required bool isLiked}) async {
    if (!_isSignedIn) return;
    try {
      if (isLiked) {
        await _client.from('saved_tracks').upsert({
          'user_id': _userId,
          'track_id': track.id.toString(),
          'track_data': track.toJson(),
        }, onConflict: 'user_id,track_id');
      } else {
        await _client
            .from('saved_tracks')
            .delete()
            .eq('user_id', _userId!)
            .eq('track_id', track.id.toString());
      }
    } catch (e) {
      appLogger.e('Failed to sync track: $e');
    }
  }

  Future<void> syncAlbum(DeezerAlbum album, {required bool isLiked}) async {
    if (!_isSignedIn) return;
    try {
      if (isLiked) {
        await _client.from('saved_albums').upsert({
          'user_id': _userId,
          'album_id': album.id.toString(),
          'album_data': album.toJson(),
        }, onConflict: 'user_id,album_id');
      } else {
        await _client
            .from('saved_albums')
            .delete()
            .eq('user_id', _userId!)
            .eq('album_id', album.id.toString());
      }
    } catch (e) {
      appLogger.e('Failed to sync album: $e');
    }
  }

  Future<void> syncArtist(
    DeezerArtist artist, {
    required bool isFollowing,
  }) async {
    if (!_isSignedIn) return;
    try {
      if (isFollowing) {
        await _client.from('saved_artists').upsert({
          'user_id': _userId,
          'artist_id': artist.id.toString(),
          'artist_data': artist.toJson(),
        }, onConflict: 'user_id,artist_id');
      } else {
        await _client
            .from('saved_artists')
            .delete()
            .eq('user_id', _userId!)
            .eq('artist_id', artist.id.toString());
      }
    } catch (e) {
      appLogger.e('Failed to sync artist: $e');
    }
  }

  Future<void> syncPlaylist(
    DeezerPlaylist playlist, {
    required bool isLiked,
  }) async {
    if (!_isSignedIn) return;
    try {
      if (isLiked) {
        await _client.from('saved_playlists').upsert({
          'user_id': _userId,
          'playlist_id': playlist.id.toString(),
          'playlist_data': playlist.toJson(),
        }, onConflict: 'user_id,playlist_id');
      } else {
        await _client
            .from('saved_playlists')
            .delete()
            .eq('user_id', _userId!)
            .eq('playlist_id', playlist.id.toString());
      }
    } catch (e) {
      appLogger.e('Failed to sync liked playlist: $e');
    }
  }

  Future<void> syncAll({
    required List<DeezerTrack> tracks,
    required List<DeezerAlbum> albums,
    required List<DeezerArtist> artists,
    required List<DeezerPlaylist> playlists,
  }) async {
    if (!_isSignedIn) return;

    try {
      // Bulk upsert tracks
      if (tracks.isNotEmpty) {
        final trackRows = tracks
            .map(
              (t) => {
                'user_id': _userId,
                'track_id': t.id.toString(),
                'track_data': t.toJson(),
              },
            )
            .toList();
        await _client
            .from('saved_tracks')
            .upsert(trackRows, onConflict: 'user_id,track_id');
      }

      // Bulk upsert albums
      if (albums.isNotEmpty) {
        final albumRows = albums
            .map(
              (a) => {
                'user_id': _userId,
                'album_id': a.id.toString(),
                'album_data': a.toJson(),
              },
            )
            .toList();
        await _client
            .from('saved_albums')
            .upsert(albumRows, onConflict: 'user_id,album_id');
      }

      // Bulk upsert artists
      if (artists.isNotEmpty) {
        final artistRows = artists
            .map(
              (a) => {
                'user_id': _userId,
                'artist_id': a.id.toString(),
                'artist_data': a.toJson(),
              },
            )
            .toList();
        await _client
            .from('saved_artists')
            .upsert(artistRows, onConflict: 'user_id,artist_id');
      }

      // Bulk upsert playlists
      if (playlists.isNotEmpty) {
        final playlistRows = playlists
            .map(
              (p) => {
                'user_id': _userId,
                'playlist_id': p.id.toString(),
                'playlist_data': p.toJson(),
              },
            )
            .toList();
        await _client
            .from('saved_playlists')
            .upsert(playlistRows, onConflict: 'user_id,playlist_id');
      }
    } catch (e) {
      appLogger.e('Failed to bulk sync library: $e');
    }
  }

  Future<void> downloadLibrary({
    required Function(DeezerTrack) onTrackFound,
    required Function(DeezerAlbum) onAlbumFound,
    required Function(DeezerArtist) onArtistFound,
    required Function(DeezerPlaylist) onPlaylistFound,
  }) async {
    if (!_isSignedIn) return;

    try {
      // Tracks
      final tracksResp = await _client
          .from('saved_tracks')
          .select()
          .eq('user_id', _userId!);
      for (final row in tracksResp) {
        try {
          final data = row['track_data'] as Map<String, dynamic>;
          final track = DeezerTrack.fromJson(data);
          onTrackFound(track);
        } catch (e) {
          appLogger.w('Skipping legacy or corrupted track: $e');
        }
      }

      // Albums
      final albumsResp = await _client
          .from('saved_albums')
          .select()
          .eq('user_id', _userId!);
      for (final row in albumsResp) {
        try {
          final data = row['album_data'] as Map<String, dynamic>;
          final album = DeezerAlbum.fromJson(data);
          onAlbumFound(album);
        } catch (e) {
          appLogger.w('Skipping legacy or corrupted album: $e');
        }
      }

      // Artists
      final artistsResp = await _client
          .from('saved_artists')
          .select()
          .eq('user_id', _userId!);
      for (final row in artistsResp) {
        try {
          final data = row['artist_data'] as Map<String, dynamic>;
          final artist = DeezerArtist.fromJson(data);
          onArtistFound(artist);
        } catch (e) {
          appLogger.w('Skipping legacy or corrupted artist: $e');
        }
      }

      // Playlists
      final playlistsResp = await _client
          .from('saved_playlists')
          .select()
          .eq('user_id', _userId!);
      for (final row in playlistsResp) {
        try {
          final data = row['playlist_data'] as Map<String, dynamic>;
          final playlist = DeezerPlaylist.fromJson(data);
          onPlaylistFound(playlist);
        } catch (e) {
          appLogger.w('Skipping legacy or corrupted playlist: $e');
        }
      }
    } catch (e) {
      appLogger.e('Failed to download library from Supabase: $e');
    }
  }
}
