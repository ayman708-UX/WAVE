import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/audiobook.dart';
import '../storage/hive_boxes.dart';
import '../storage/library_providers.dart';
import '../../features/audiobooks/services/audiobook_providers.dart';
import 'supabase_library_sync.dart';
import 'supabase_playlist_sync.dart';
import 'supabase_audiobook_sync.dart';
import 'supabase_profile_service.dart';
import '../utils/app_logger.dart';

final syncManagerProvider = Provider<SyncManager>((ref) {
  return SyncManager(ref);
});

class SyncManager {
  final Ref _ref;
  bool _isSyncing = false;

  SyncManager(this._ref);

  /// Helper to convert complex objects into clean Hive-serializable Map JSON
  Map<String, dynamic> _deepJson(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  /// Perform a full 2-way sync between local Hive storage and Supabase cloud tables.
  Future<void> performFullSync() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return;
    if (_isSyncing) return;

    _isSyncing = true;
    appLogger.i('Starting full Supabase account & audiobook sync...');

    try {
      final librarySync = _ref.read(supabaseLibrarySyncProvider);
      final playlistSync = _ref.read(supabasePlaylistSyncProvider);
      final audiobookSync = _ref.read(supabaseAudiobookSyncProvider);

      final tracksBox = Hive.box<dynamic>(HiveBoxes.likedTracks);
      final albumsBox = Hive.box<dynamic>(HiveBoxes.likedAlbums);
      final artistsBox = Hive.box<dynamic>(HiveBoxes.followedArtists);
      final likedPlaylistsBox = Hive.box<dynamic>(HiveBoxes.likedPlaylists);
      final playlistsBox = Hive.box<dynamic>(HiveBoxes.playlists);
      final playlistTracksBox = Hive.box<dynamic>(HiveBoxes.playlistTracks);
      final likedAudiobooksBox = Hive.box<dynamic>(HiveBoxes.likedAudiobooks);
      final audiobookProgressBox = Hive.box<dynamic>(HiveBoxes.audiobookProgress);

      // -----------------------------------------------------------------------
      // 1. Download & Merge Remote Data -> Local Hive
      // -----------------------------------------------------------------------

      // Download library (tracks, albums, artists, liked playlists)
      await librarySync.downloadLibrary(
        onTrackFound: (track) async {
          final key = track.id < 0 ? track.id.toString() : track.id;
          if (!tracksBox.containsKey(key)) {
            await tracksBox.put(key, _deepJson(track.toJson()));
          }
        },
        onAlbumFound: (album) async {
          if (!albumsBox.containsKey(album.id)) {
            await albumsBox.put(album.id, _deepJson(album.toJson()));
          }
        },
        onArtistFound: (artist) async {
          if (!artistsBox.containsKey(artist.id)) {
            await artistsBox.put(artist.id, _deepJson(artist.toJson()));
          }
        },
        onPlaylistFound: (playlist) async {
          if (!likedPlaylistsBox.containsKey(playlist.id.toString())) {
            await likedPlaylistsBox.put(
              playlist.id.toString(),
              _deepJson(playlist.toJson()),
            );
          }
        },
      );

      // Download created user playlists
      await playlistSync.downloadPlaylists(
        onPlaylistFound: (playlist, tracks) async {
          final existingTitles = playlistsBox.values
              .whereType<Map>()
              .map((m) => m['title']?.toString() ?? '')
              .toSet();
          if (!existingTitles.contains(playlist.title)) {
            await playlistsBox.put(
              playlist.id.toString(),
              _deepJson(playlist.toJson()),
            );
            await playlistTracksBox.put(
              playlist.id.toString(),
              tracks.map((t) => _deepJson(t.toJson())).toList(),
            );
          }
        },
      );

      // Download audiobooks & audiobook progress
      await audiobookSync.downloadAudiobooks(
        onAudiobookFound: (book) async {
          if (!likedAudiobooksBox.containsKey(book.uuid)) {
            await likedAudiobooksBox.put(book.uuid, _deepJson(book.toJson()));
          }
        },
        onProgressFound: (progress) async {
          final existingRaw = audiobookProgressBox.get(progress.audiobook.uuid);
          if (existingRaw is Map) {
            final localProgress = AudiobookProgress.fromJson(
              _deepJson(Map<String, dynamic>.from(existingRaw)),
            );
            // Only overwrite if remote updated_at timestamp is newer
            if (progress.updatedAt > localProgress.updatedAt) {
              await audiobookProgressBox.put(
                progress.audiobook.uuid,
                _deepJson(progress.toJson()),
              );
            }
          } else {
            await audiobookProgressBox.put(
              progress.audiobook.uuid,
              _deepJson(progress.toJson()),
            );
          }
        },
      );

      // -----------------------------------------------------------------------
      // 2. Upload & Bulk Upsert Local Data -> Supabase Cloud
      // -----------------------------------------------------------------------

      final playlists = _ref.read(userPlaylistsProvider);
      final trackMap = _ref.read(localPlaylistTracksProvider);
      await playlistSync.syncAllPlaylists(playlists: playlists, trackMap: trackMap);

      final likedTracks = _ref.read(likedTracksProvider);
      final likedAlbums = _ref.read(likedAlbumsProvider);
      final following = _ref.read(followedArtistsProvider);
      final likedPlaylists = _ref.read(likedPlaylistsProvider);
      await librarySync.syncAll(
        tracks: likedTracks,
        albums: likedAlbums,
        artists: following,
        playlists: likedPlaylists,
      );

      final likedAudiobooks = _ref.read(likedAudiobooksProvider);
      final audiobookProgressList = _ref.read(audiobookProgressProvider);
      await audiobookSync.syncAllAudiobooks(
        books: likedAudiobooks,
        progressList: audiobookProgressList,
      );

      // -----------------------------------------------------------------------
      // 3. Refresh Riverpod UI state
      // -----------------------------------------------------------------------
      _ref.invalidate(likedTracksProvider);
      _ref.invalidate(likedAlbumsProvider);
      _ref.invalidate(followedArtistsProvider);
      _ref.invalidate(likedPlaylistsProvider);
      _ref.invalidate(userPlaylistsProvider);
      _ref.invalidate(localPlaylistTracksProvider);
      _ref.invalidate(likedAudiobooksProvider);
      _ref.invalidate(audiobookProgressProvider);
      _ref.invalidate(currentProfileProvider);

      appLogger.i('Full Supabase account & audiobook sync completed successfully.');
    } catch (e) {
      appLogger.e('Error during full sync: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
