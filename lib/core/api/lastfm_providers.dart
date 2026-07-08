import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/recently_played.dart';
import 'deezer_api_client.dart';
import 'lastfm_api_client.dart';
import 'models/deezer_track.dart';

final lastfmApiClientProvider = Provider<LastfmApiClient>((ref) {
  return LastfmApiClient();
});

final recommendedTracksProvider = FutureProvider<List<DeezerTrack>>((
  ref,
) async {
  final recentlyPlayed = ref.watch(recentlyPlayedProvider);
  final lastfmApi = ref.watch(lastfmApiClientProvider);
  final deezerApi = ref.watch(deezerApiClientProvider);

  // Fallback function to use chart tracks if recommendations fail
  Future<List<DeezerTrack>> getFallback() async {
    try {
      final tracks = await deezerApi.getChartTracks(limit: 15);
      // Shuffle them so it feels fresh
      tracks.shuffle();
      return tracks.take(10).toList();
    } catch (_) {
      return [];
    }
  }

  // Find the most recently played track
  final recentTracks = recentlyPlayed.where((e) => e.kind == 'track').toList();
  if (recentTracks.isEmpty) {
    return getFallback();
  }

  final seedTrack = recentTracks.first;
  final artist = seedTrack.subtitle ?? '';
  final trackName = seedTrack.title;

  if (artist.isEmpty) return getFallback();

  // Get similar tracks from Last.fm
  final similar = await lastfmApi.getSimilarTracks(trackName, artist);
  if (similar.isEmpty) return getFallback();

  // Resolve to Deezer tracks
  final deezerTracks = <DeezerTrack>[];
  for (final t in similar) {
    final tName = t['name'] ?? '';
    final tArtist = t['artist'] ?? '';
    if (tName.isEmpty || tArtist.isEmpty) continue;

    try {
      final searchRes = await deezerApi.searchTracks(
        'artist:"$tArtist" track:"$tName"',
      );
      if (searchRes.isNotEmpty) {
        // Take the first matching track
        deezerTracks.add(searchRes.first);
      }
    } catch (e) {
      // Ignore search errors for individual tracks
    }
    if (deezerTracks.length >= 10) {
      break; // Limit to 10 recommended tracks
    }
  }

  if (deezerTracks.isEmpty) {
    return getFallback();
  }

  return deezerTracks;
});
