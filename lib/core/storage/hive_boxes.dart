import 'package:hive_flutter/hive_flutter.dart';

/// Names of every Hive box used by the app. Keep box reads/writes typed
/// against these constants; never hard-code the strings elsewhere.
class HiveBoxes {
  HiveBoxes._();

  /// User-level settings (active theme id, crossfade seconds, etc.).
  static const String settings = 'settings';

  /// Locally liked tracks (track id -> raw json map).
  static const String likedTracks = 'liked_tracks';

  /// Locally liked albums.
  static const String likedAlbums = 'liked_albums';

  /// Locally liked playlists.
  static const String likedPlaylists = 'liked_playlists';

  /// Locally liked audiobooks.
  static const String likedAudiobooks = 'liked_audiobooks';

  /// Followed artist ids.
  static const String followedArtists = 'followed_artists';

  /// User-created playlists (playlist id -> json).
  static const String playlists = 'playlists';

  /// User-created playlist tracks (playlist id -> list of track json keys).
  static const String playlistTracks = 'playlist_tracks';

  /// Recent search queries (string list).
  static const String recentSearches = 'recent_searches';

  /// Recently played items (json list).
  static const String recentlyPlayed = 'recently_played';

  /// Algorithm / Flow tuner settings.
  static const String algorithm = 'algorithm';

  /// Banned artists for the algorithm.
  static const String bannedArtists = 'banned_artists';

  /// Downloaded track metadata (track json map).
  static const String downloads = 'downloads';

  /// Cached Deezer track id -> YouTube video id matches.
  /// This reduces repeat YouTube searching on each device.
  static const String youtubeMatches = 'youtube_matches';
  
  /// Audiobook playback progress (book uuid -> json).
  static const String audiobookProgress = 'audiobook_progress';

  static Future<void> openAll() async {
    await Hive.initFlutter();

    await Future.wait<void>(<Future<void>>[
      Hive.openBox<dynamic>(settings),
      Hive.openBox<dynamic>(likedTracks),
      Hive.openBox<dynamic>(likedAlbums),
      Hive.openBox<dynamic>(likedPlaylists),
      Hive.openBox<dynamic>(followedArtists),
      Hive.openBox<dynamic>(playlists),
      Hive.openBox<dynamic>(playlistTracks),
      Hive.openBox<dynamic>(recentSearches),
      Hive.openBox<dynamic>(recentlyPlayed),
      Hive.openBox<dynamic>(algorithm),
      Hive.openBox<dynamic>(bannedArtists),
      Hive.openBox<dynamic>(downloads),
      Hive.openBox<dynamic>(youtubeMatches),
      Hive.openBox<dynamic>(likedAudiobooks),
      Hive.openBox<dynamic>(audiobookProgress),
    ]);
  }
}
