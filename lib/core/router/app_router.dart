import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models/community_playlist.dart';
import '../../core/api/models/deezer_genre.dart';
import '../../features/album/album_screen.dart';
import '../../features/artist/artist_screen.dart';
import '../../features/discover/discover_screen.dart';
import '../../features/discover/genre_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/player/now_playing_screen.dart';
import '../../features/playlist/community_playlist_screen.dart';
import '../../features/playlist/playlist_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/profile/user_profile_screen.dart';
import '../../features/playlist/shared_playlist_screen.dart';
import '../../features/audiobooks/audiobook_screen.dart';
import '../../core/models/audiobook.dart';
import '../../widgets/app_shell.dart';

/// Route name constants — never hardcode paths at call sites.
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String discover = '/discover';
  static const String search = '/search';
  static const String library = '/library';
  static const String settings = '/settings';
  static const String nowPlaying = '/now-playing';
  static const String artist = '/artist/:id';
  static const String album = '/album/:id';
  static const String playlist = '/playlist/:id';
  static const String communityPlaylist = '/community-playlist';
  static const String genre = '/genre';
  static const String auth = '/auth';
  static const String userProfile = '/user/:id';
  static const String sharedPlaylist = '/shared-playlist/:id';
  static const String audiobook = '/audiobook';

  static String artistPath(int id) => '/artist/$id';
  static String albumPath(int id) => '/album/$id';
  static String playlistPath(int id) => '/playlist/$id';
  static String userProfilePath(String id) => '/user/$id';
  static String sharedPlaylistPath(String id) => '/shared-playlist/$id';
}

/// Shared keys for nested navigators.
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'shell',
);

/// Builds a [CustomTransitionPage] using a fade-through transition. Used as
/// the default for tab switches.
CustomTransitionPage<T> _fadePage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondary, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

/// Bottom-to-top sheet-style transition used for detail pages (album,
/// artist, playlist, now-playing).
CustomTransitionPage<T> _sheetPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondary, child) {
      final tween = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

/// Subtle scale + fade used for Settings.
CustomTransitionPage<T> _settingsPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondary, child) {
      final scale = Tween<double>(
        begin: 1.05,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: scale, child: child),
      );
    },
  );
}

/// Application-wide [GoRouter] configuration.
final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.home,
  routes: <RouteBase>[
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.home,
          pageBuilder: (context, state) =>
              _fadePage(key: state.pageKey, child: const HomeScreen()),
        ),

        GoRoute(
          path: AppRoutes.discover,
          pageBuilder: (context, state) =>
              _fadePage(key: state.pageKey, child: const DiscoverScreen()),
        ),
        GoRoute(
          path: AppRoutes.search,
          pageBuilder: (context, state) =>
              _fadePage(key: state.pageKey, child: const SearchScreen()),
        ),
        GoRoute(
          path: AppRoutes.library,
          pageBuilder: (context, state) =>
              _fadePage(key: state.pageKey, child: const LibraryScreen()),
        ),
        GoRoute(
          path: AppRoutes.artist,
          pageBuilder: (context, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return _fadePage(
              key: ValueKey('artist_$id'),
              child: ArtistScreen(artistId: id),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.album,
          pageBuilder: (context, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return _fadePage(
              key: ValueKey('album_$id'),
              child: AlbumScreen(albumId: id),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.playlist,
          pageBuilder: (context, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return _fadePage(
              key: ValueKey('playlist_$id'),
              child: PlaylistScreen(playlistId: id),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.genre,
          pageBuilder: (context, state) {
            final genre = state.extra as DeezerGenre?;
            if (genre == null) {
              return _fadePage(
                key: state.pageKey,
                child: const Scaffold(
                  body: Center(child: Text('Invalid genre')),
                ),
              );
            }
            return _fadePage(
              key: state.pageKey,
              child: GenreScreen(genre: genre),
            );
          },
        ),

        GoRoute(
          path: AppRoutes.userProfile,
          pageBuilder: (context, state) {
            final userId = state.pathParameters['id'] ?? '';
            return _fadePage(
              key: state.pageKey,
              child: UserProfileScreen(userId: userId),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.sharedPlaylist,
          pageBuilder: (context, state) {
            final playlistId = state.pathParameters['id'] ?? '';
            return _fadePage(
              key: state.pageKey,
              child: SharedPlaylistScreen(playlistId: playlistId),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.communityPlaylist,
          pageBuilder: (context, state) {
            // Retrieve the extra data passed
            final cp = state.extra as CommunityPlaylist?;
            if (cp == null) {
              return _fadePage(
                key: state.pageKey,
                child: const Scaffold(
                  body: Center(child: Text('Invalid playlist')),
                ),
              );
            }
            return _fadePage(
              key: state.pageKey,
              child: CommunityPlaylistScreen(communityPlaylist: cp),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.audiobook,
          pageBuilder: (context, state) {
            Audiobook? book;
            bool autoPlay = false;
            if (state.extra is Audiobook) {
              book = state.extra as Audiobook;
            } else if (state.extra is Map<String, dynamic>) {
              final map = state.extra as Map<String, dynamic>;
              book = map['audiobook'] as Audiobook?;
              autoPlay = map['autoPlay'] == true;
            }
            if (book == null) {
              return _fadePage(
                key: state.pageKey,
                child: const Scaffold(
                  body: Center(child: Text('Invalid audiobook')),
                ),
              );
            }
            return _fadePage(
              key: state.pageKey,
              child: AudiobookScreen(audiobook: book, autoPlay: autoPlay),
            );
          },
        ),
      ],
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: AppRoutes.settings,
      pageBuilder: (context, state) =>
          _settingsPage(key: state.pageKey, child: const SettingsScreen()),
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: AppRoutes.nowPlaying,
      pageBuilder: (context, state) =>
          _sheetPage(key: state.pageKey, child: const NowPlayingScreen()),
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: AppRoutes.auth,
      pageBuilder: (context, state) =>
          _sheetPage(key: state.pageKey, child: const AuthScreen()),
    ),
  ],
);
