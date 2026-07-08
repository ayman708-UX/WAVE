import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/library_providers.dart';
import '../storage/recently_played.dart';
import 'deezer_api_client.dart';
import 'models/deezer_album.dart';
import 'models/deezer_artist.dart';
import 'models/deezer_genre.dart';
import 'models/deezer_playlist.dart';
import 'models/deezer_track.dart';

/// Charts ----------------------------------------------------------------------

final chartTracksProvider = FutureProvider<List<DeezerTrack>>((ref) async {
  return ref.watch(deezerApiClientProvider).getChartTracks(limit: 100);
});

final chartAlbumsProvider = FutureProvider<List<DeezerAlbum>>((ref) async {
  return ref.watch(deezerApiClientProvider).getChartAlbums(limit: 25);
});

final chartArtistsProvider = FutureProvider<List<DeezerArtist>>((ref) async {
  return ref.watch(deezerApiClientProvider).getChartArtists(limit: 25);
});

final chartPlaylistsProvider = FutureProvider<List<DeezerPlaylist>>((
  ref,
) async {
  return ref.watch(deezerApiClientProvider).getChartPlaylists(limit: 25);
});

/// Editorial selection (new releases live here).
final editorialSelectionProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  return ref.watch(deezerApiClientProvider).getEditorialSelection();
});

/// New releases — fetched directly from editorial releases endpoint.
final newReleasesProvider = FutureProvider<List<DeezerAlbum>>((ref) async {
  return ref.watch(deezerApiClientProvider).getNewReleases();
});

/// Genres ---------------------------------------------------------------------

final genresProvider = FutureProvider<List<DeezerGenre>>((ref) async {
  return ref.watch(deezerApiClientProvider).getGenres();
});

/// Detail endpoints (parameterised) ------------------------------------------

final albumProvider = FutureProvider.family<DeezerAlbum, int>((ref, id) async {
  return ref.watch(deezerApiClientProvider).getAlbum(id);
});

final albumTracksProvider = FutureProvider.family<List<DeezerTrack>, int>((
  ref,
  id,
) async {
  return ref.watch(deezerApiClientProvider).getAlbumTracks(id);
});

final artistProvider = FutureProvider.family<DeezerArtist, int>((
  ref,
  id,
) async {
  return ref.watch(deezerApiClientProvider).getArtist(id);
});

final artistTopTracksProvider = FutureProvider.family<List<DeezerTrack>, int>((
  ref,
  id,
) async {
  return ref.watch(deezerApiClientProvider).getArtistTopTracks(id);
});

final artistAlbumsProvider = FutureProvider.family<List<DeezerAlbum>, int>((
  ref,
  id,
) async {
  return ref.watch(deezerApiClientProvider).getArtistAlbums(id);
});

final relatedArtistsProvider = FutureProvider.family<List<DeezerArtist>, int>((
  ref,
  id,
) async {
  return ref.watch(deezerApiClientProvider).getRelatedArtists(id);
});

final playlistProvider = FutureProvider.family<DeezerPlaylist, int>((
  ref,
  id,
) async {
  if (id < 0) {
    try {
      return ref.watch(userPlaylistsProvider).firstWhere((p) => p.id == id);
    } catch (_) {
      return ref.watch(likedPlaylistsProvider).firstWhere((p) => p.id == id);
    }
  }
  return ref.watch(deezerApiClientProvider).getPlaylist(id);
});

final playlistTracksProvider = FutureProvider.family<List<DeezerTrack>, int>((
  ref,
  id,
) async {
  if (id < 0) {
    return ref.watch(localPlaylistTracksProvider)[id] ?? [];
  }
  return ref.watch(deezerApiClientProvider).getPlaylistTracks(id);
});

final genreRadioTracksProvider = FutureProvider.family<List<DeezerTrack>, int>((
  ref,
  id,
) async {
  return ref.watch(deezerApiClientProvider).getGenreRadioTracks(id);
});

final madeForYouAlbumsProvider = FutureProvider<List<DeezerAlbum>>((ref) async {
  final api = ref.watch(deezerApiClientProvider);
  final recent = ref.watch(recentlyPlayedProvider);

  final artistIds = <int>{};

  // Pick up to 5 random recent items to extract artists
  final randomRecent = recent.toList()..shuffle();
  for (final entry in randomRecent.take(5)) {
    try {
      if (entry.kind == 'artist') {
        artistIds.add(entry.id);
      } else if (entry.kind == 'album') {
        final album = await api.getAlbum(entry.id);
        if (album.artist != null) artistIds.add(album.artist!.id);
      } else if (entry.kind == 'track') {
        final track = await api.getTrack(entry.id);
        if (track.artist != null) artistIds.add(track.artist!.id);
      }
    } catch (_) {
      // Ignore errors fetching individual items
    }
  }

  // If no artists could be found from recent, fallback to chart artists
  if (artistIds.isEmpty) {
    try {
      final charts = await api.getChartArtists(limit: 5);
      for (final a in charts) {
        artistIds.add(a.id);
      }
    } catch (_) {}
  }

  // Fetch related artists for these artists
  final relatedArtists = <DeezerArtist>[];
  for (final id in artistIds) {
    try {
      final related = await api.getRelatedArtists(id);
      relatedArtists.addAll(related);
    } catch (_) {}
  }

  // Pick up to 5 random related artists
  relatedArtists.shuffle();
  final selectedRelated = relatedArtists.take(5).toList();

  // Fetch albums for these selected related artists
  final albums = <DeezerAlbum>[];
  for (final a in selectedRelated) {
    try {
      final artistAlbums = await api.getArtistAlbums(a.id);
      albums.addAll(artistAlbums);
    } catch (_) {}
  }

  albums.shuffle();
  return albums;
});
