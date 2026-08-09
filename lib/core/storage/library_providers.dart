import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../api/models/deezer_album.dart';
import '../api/models/deezer_artist.dart';
import '../api/models/deezer_playlist.dart';
import '../api/models/deezer_track.dart';
import '../api/models/deezer_user.dart';
import '../auth/supabase_library_sync.dart';
import '../auth/supabase_auth_service.dart';
import '../auth/supabase_playlist_sync.dart';
import 'hive_boxes.dart';

/// Ensures complex models are recursively converted to Maps before Hive storage.
/// This prevents "unknown type" errors when nested objects (like Artist in Track)
/// aren't manually converted to JSON.
Map<String, dynamic> _deepJson(Map<String, dynamic> json) {
  return jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
}

/// Sort options for the liked tracks list.
enum LikedSort { recent, alphabetical, artist, duration }

// ---------------------------------------------------------------------------
// Liked tracks ------------------------------------------------------------

class LikedTracksNotifier extends Notifier<List<DeezerTrack>> {
  @override
  List<DeezerTrack> build() {
    final box = Hive.box<dynamic>(HiveBoxes.likedTracks);
    return box.values
        .whereType<Map>()
        .map(
          (m) => DeezerTrack.fromJson(_deepJson(Map<String, dynamic>.from(m))),
        )
        .toList(growable: false);
  }

  bool isLiked(int id) => state.any((t) => t.id == id);

  Future<void> toggle(DeezerTrack track) async {
    final box = Hive.box<dynamic>(HiveBoxes.likedTracks);
    final key = track.id < 0 ? track.id.toString() : track.id;
    if (isLiked(track.id)) {
      await box.delete(key);
      state = state.where((t) => t.id != track.id).toList(growable: false);
      ref.read(supabaseLibrarySyncProvider).syncTrack(track, isLiked: false);
    } else {
      await box.put(key, _deepJson(track.toJson()));
      state = <DeezerTrack>[track, ...state];
      ref.read(supabaseLibrarySyncProvider).syncTrack(track, isLiked: true);
    }
  }

  Future<void> remove(int id) async {
    final key = id < 0 ? id.toString() : id;
    await Hive.box<dynamic>(HiveBoxes.likedTracks).delete(key);
    final track = state.firstWhere((t) => t.id == id);
    state = state.where((t) => t.id != id).toList(growable: false);
    ref.read(supabaseLibrarySyncProvider).syncTrack(track, isLiked: false);
  }
}

final likedTracksProvider =
    NotifierProvider<LikedTracksNotifier, List<DeezerTrack>>(
      LikedTracksNotifier.new,
    );

final likedSortProvider = NotifierProvider<LikedSortNotifier, LikedSort>(
  LikedSortNotifier.new,
);

class LikedSortNotifier extends Notifier<LikedSort> {
  @override
  LikedSort build() => LikedSort.recent;
  void set(LikedSort s) => state = s;
}

/// Read-only sorted view derived from `likedTracksProvider` + sort choice.
final likedTracksSortedProvider = Provider<List<DeezerTrack>>((ref) {
  final list = <DeezerTrack>[...ref.watch(likedTracksProvider)];
  switch (ref.watch(likedSortProvider)) {
    case LikedSort.recent:
      // Already in insertion order (newest first).
      break;
    case LikedSort.alphabetical:
      list.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      break;
    case LikedSort.artist:
      list.sort(
        (a, b) => (a.artist?.name ?? '').toLowerCase().compareTo(
          (b.artist?.name ?? '').toLowerCase(),
        ),
      );
      break;
    case LikedSort.duration:
      list.sort((a, b) => (a.duration ?? 0).compareTo(b.duration ?? 0));
      break;
  }
  return list;
});

// ---------------------------------------------------------------------------
// Liked albums ------------------------------------------------------------

class LikedAlbumsNotifier extends Notifier<List<DeezerAlbum>> {
  @override
  List<DeezerAlbum> build() {
    final box = Hive.box<dynamic>(HiveBoxes.likedAlbums);
    return box.values
        .whereType<Map>()
        .map(
          (m) => DeezerAlbum.fromJson(_deepJson(Map<String, dynamic>.from(m))),
        )
        .toList(growable: false);
  }

  bool isLiked(int id) => state.any((a) => a.id == id);

  Future<void> toggle(DeezerAlbum album) async {
    final box = Hive.box<dynamic>(HiveBoxes.likedAlbums);
    if (isLiked(album.id)) {
      await box.delete(album.id);
      state = state.where((a) => a.id != album.id).toList(growable: false);
      ref.read(supabaseLibrarySyncProvider).syncAlbum(album, isLiked: false);
    } else {
      await box.put(album.id, _deepJson(album.toJson()));
      state = <DeezerAlbum>[album, ...state];
      ref.read(supabaseLibrarySyncProvider).syncAlbum(album, isLiked: true);
    }
  }
}

final likedAlbumsProvider =
    NotifierProvider<LikedAlbumsNotifier, List<DeezerAlbum>>(
      LikedAlbumsNotifier.new,
    );

// ---------------------------------------------------------------------------
// Liked playlists ---------------------------------------------------------

class LikedPlaylistsNotifier extends Notifier<List<DeezerPlaylist>> {
  @override
  List<DeezerPlaylist> build() {
    final box = Hive.box<dynamic>(HiveBoxes.likedPlaylists);
    return box.values
        .whereType<Map>()
        .map(
          (m) =>
              DeezerPlaylist.fromJson(_deepJson(Map<String, dynamic>.from(m))),
        )
        .toList(growable: false);
  }

  bool isLiked(int id) => state.any((p) => p.id == id);

  Future<void> toggle(DeezerPlaylist playlist) async {
    final box = Hive.box<dynamic>(HiveBoxes.likedPlaylists);
    final key = playlist.id.toString();
    if (isLiked(playlist.id)) {
      await box.delete(key);
      await box.delete(playlist.id);
      state = state.where((p) => p.id != playlist.id).toList(growable: false);
      ref
          .read(supabaseLibrarySyncProvider)
          .syncPlaylist(playlist, isLiked: false);
    } else {
      await box.put(key, _deepJson(playlist.toJson()));
      state = <DeezerPlaylist>[playlist, ...state];
      ref
          .read(supabaseLibrarySyncProvider)
          .syncPlaylist(playlist, isLiked: true);
    }
  }
}

final likedPlaylistsProvider =
    NotifierProvider<LikedPlaylistsNotifier, List<DeezerPlaylist>>(
      LikedPlaylistsNotifier.new,
    );

// ---------------------------------------------------------------------------
// Followed artists --------------------------------------------------------

class FollowedArtistsNotifier extends Notifier<List<DeezerArtist>> {
  @override
  List<DeezerArtist> build() {
    final box = Hive.box<dynamic>(HiveBoxes.followedArtists);
    return box.values
        .whereType<Map>()
        .map(
          (m) => DeezerArtist.fromJson(_deepJson(Map<String, dynamic>.from(m))),
        )
        .toList(growable: false);
  }

  bool isFollowing(int id) => state.any((a) => a.id == id);

  Future<void> toggle(DeezerArtist artist) async {
    final box = Hive.box<dynamic>(HiveBoxes.followedArtists);
    if (isFollowing(artist.id)) {
      await box.delete(artist.id);
      state = state.where((a) => a.id != artist.id).toList(growable: false);
      ref
          .read(supabaseLibrarySyncProvider)
          .syncArtist(artist, isFollowing: false);
    } else {
      await box.put(artist.id, _deepJson(artist.toJson()));
      state = <DeezerArtist>[artist, ...state];
      ref
          .read(supabaseLibrarySyncProvider)
          .syncArtist(artist, isFollowing: true);
    }
  }
}

final followedArtistsProvider =
    NotifierProvider<FollowedArtistsNotifier, List<DeezerArtist>>(
      FollowedArtistsNotifier.new,
    );

// ---------------------------------------------------------------------------
// User playlists ----------------------------------------------------------

class UserPlaylistsNotifier extends Notifier<List<DeezerPlaylist>> {
  @override
  List<DeezerPlaylist> build() {
    final box = Hive.box<dynamic>(HiveBoxes.playlists);
    return box.values
        .whereType<Map>()
        .map(
          (m) =>
              DeezerPlaylist.fromJson(_deepJson(Map<String, dynamic>.from(m))),
        )
        .toList(growable: false);
  }

  Future<DeezerPlaylist> create({
    required String title,
    String? description,
    bool public = true,
    String? coverUrl,
  }) async {
    // Local id space — negative to avoid collisions with real Deezer ids.
    // Use a string key for Hive to avoid the 32-bit integer range limit.
    final id = -DateTime.now().millisecondsSinceEpoch;
    final pl = DeezerPlaylist(
      id: id,
      title: title,
      description: description,
      public: public,
      nbTracks: 0,
      picture: coverUrl,
      pictureMedium: coverUrl,
      pictureBig: coverUrl,
      creator: const DeezerUser(id: 0, name: 'You'),
    );
    await Hive.box<dynamic>(
      HiveBoxes.playlists,
    ).put(id.toString(), _deepJson(pl.toJson()));
    state = <DeezerPlaylist>[pl, ...state];

    if (ref.read(isSignedInProvider)) {
      ref
          .read(supabasePlaylistSyncProvider)
          .syncPlaylist(playlist: pl, tracks: [], isPublic: public);
    }

    return pl;
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = <DeezerPlaylist>[...state];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = list;
    final box = Hive.box<dynamic>(HiveBoxes.playlists);
    await box.clear();
    for (final p in list) {
      await box.put(p.id.toString(), _deepJson(p.toJson()));
    }
  }

  Future<void> delete(int id) async {
    final title = state
        .firstWhere(
          (p) => p.id == id,
          orElse: () => const DeezerPlaylist(id: 0, title: '', nbTracks: 0),
        )
        .title;

    await Hive.box<dynamic>(HiveBoxes.playlists).delete(id.toString());
    await Hive.box<dynamic>(HiveBoxes.playlistTracks).delete(id.toString());
    state = state.where((p) => p.id != id).toList(growable: false);

    if (ref.read(isSignedInProvider) && title.isNotEmpty) {
      ref.read(supabasePlaylistSyncProvider).deletePlaylist(title);
    }
  }

  Future<void> importPlaylist(
    DeezerPlaylist pl,
    List<DeezerTrack> tracks,
  ) async {
    if (state.any((p) => p.id == pl.id)) return; // Already imported
    await Hive.box<dynamic>(
      HiveBoxes.playlists,
    ).put(pl.id.toString(), _deepJson(pl.toJson()));
    state = <DeezerPlaylist>[pl, ...state];

    final tracksBox = Hive.box<dynamic>(HiveBoxes.playlistTracks);
    await tracksBox.put(
      pl.id.toString(),
      tracks.map((t) => _deepJson(t.toJson())).toList(),
    );
  }

  Future<void> updatePlaylist(
    int id, {
    required String title,
    String? description,
  }) async {
    final list = state
        .map((p) {
          if (p.id == id) {
            return p.copyWith(title: title, description: description);
          }
          return p;
        })
        .toList(growable: false);

    state = list;

    final box = Hive.box<dynamic>(HiveBoxes.playlists);
    final target = list.firstWhere((p) => p.id == id);
    final oldTitle = state.firstWhere((p) => p.id == id).title;

    await box.put(id.toString(), _deepJson(target.toJson()));

    if (ref.read(isSignedInProvider)) {
      final tracks = ref.read(localPlaylistTracksProvider)[id] ?? [];
      ref
          .read(supabasePlaylistSyncProvider)
          .syncPlaylist(
            playlist: target,
            tracks: tracks,
            isPublic: target.public ?? true,
            oldTitle: oldTitle != target.title ? oldTitle : null,
          );
    }
  }
}

final userPlaylistsProvider =
    NotifierProvider<UserPlaylistsNotifier, List<DeezerPlaylist>>(
      UserPlaylistsNotifier.new,
    );

// ---------------------------------------------------------------------------
// Local playlist tracks ---------------------------------------------------

class LocalPlaylistTracksNotifier
    extends Notifier<Map<int, List<DeezerTrack>>> {
  @override
  Map<int, List<DeezerTrack>> build() {
    final box = Hive.box<dynamic>(HiveBoxes.playlistTracks);
    final map = <int, List<DeezerTrack>>{};
    for (final key in box.keys) {
      if (key is String) {
        final id = int.tryParse(key);
        if (id != null) {
          final rawList = box.get(key);
          if (rawList is List) {
            map[id] = rawList
                .whereType<Map>()
                .map(
                  (m) => DeezerTrack.fromJson(
                    _deepJson(Map<String, dynamic>.from(m)),
                  ),
                )
                .toList(growable: false);
          }
        }
      }
    }
    return map;
  }

  Future<void> addTrack(int playlistId, DeezerTrack track) async {
    await addTracks(playlistId, <DeezerTrack>[track]);
  }

  Future<void> addTracks(int playlistId, List<DeezerTrack> tracks) async {
    if (tracks.isEmpty) return;

    final currentList = state[playlistId] ?? <DeezerTrack>[];
    final existingIds = currentList.map((t) => t.id).toSet();
    final toAdd = tracks
        .where((track) => !existingIds.contains(track.id))
        .toList(growable: false);

    if (toAdd.isEmpty) return;

    final newList = <DeezerTrack>[...currentList, ...toAdd];

    state = <int, List<DeezerTrack>>{...state, playlistId: newList};

    await _persistPlaylistTracks(playlistId, newList);
  }

  Future<void> removeTrack(int playlistId, int trackId) async {
    await removeTracks(playlistId, <int>[trackId]);
  }

  Future<void> removeTracks(int playlistId, Iterable<int> trackIds) async {
    final ids = trackIds.toSet();
    if (ids.isEmpty) return;

    final currentList = state[playlistId] ?? <DeezerTrack>[];
    final newList = currentList
        .where((t) => !ids.contains(t.id))
        .toList(growable: false);

    state = <int, List<DeezerTrack>>{...state, playlistId: newList};

    await _persistPlaylistTracks(playlistId, newList);
  }

  Future<void> _persistPlaylistTracks(
    int playlistId,
    List<DeezerTrack> tracks,
  ) async {
    final tracksBox = Hive.box<dynamic>(HiveBoxes.playlistTracks);
    await tracksBox.put(
      playlistId.toString(),
      tracks.map((t) => _deepJson(t.toJson())).toList(),
    );

    await _writePlaylistMetadata(playlistId, tracks);

    // playlistProvider(id) watches userPlaylistsProvider for local playlists,
    // so this refreshes open local playlist headers and list screens.
    ref.invalidate(userPlaylistsProvider);
  }

  Future<void> reorderTrack(int playlistId, int oldIndex, int newIndex) async {
    final currentList = state[playlistId] ?? <DeezerTrack>[];
    final newList = <DeezerTrack>[...currentList];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = newList.removeAt(oldIndex);
    newList.insert(newIndex, item);

    state = {...state, playlistId: newList};

    final box = Hive.box<dynamic>(HiveBoxes.playlistTracks);
    await box.put(
      playlistId.toString(),
      newList.map((t) => _deepJson(t.toJson())).toList(),
    );
  }

  Future<void> _writePlaylistMetadata(
    int playlistId,
    List<DeezerTrack> tracks,
  ) async {
    final currentPlaylists = ref.read(userPlaylistsProvider);
    final idx = currentPlaylists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;

    final pl = currentPlaylists[idx];
    final newPicture = tracks.isEmpty
        ? null
        : (tracks.first.album?.coverBig ??
              tracks.first.album?.coverMedium ??
              tracks.first.album?.cover);

    final updatedPl = pl.copyWith(
      nbTracks: tracks.length,
      picture: newPicture,
      pictureMedium: newPicture,
      pictureBig: newPicture,
    );

    await Hive.box<dynamic>(
      HiveBoxes.playlists,
    ).put(playlistId.toString(), _deepJson(updatedPl.toJson()));

    if (ref.read(isSignedInProvider)) {
      ref
          .read(supabasePlaylistSyncProvider)
          .syncPlaylist(
            playlist: updatedPl,
            tracks: tracks,
            isPublic: updatedPl.public ?? true,
          );
    }
  }
}

final localPlaylistTracksProvider =
    NotifierProvider<LocalPlaylistTracksNotifier, Map<int, List<DeezerTrack>>>(
      LocalPlaylistTracksNotifier.new,
    );

/// Local playlists that already contain the given track.
/// Used by Downloads and the Add/Manage Playlist sheet.
final playlistsForTrackProvider = Provider.family<List<DeezerPlaylist>, int>((
  ref,
  trackId,
) {
  final playlists = ref.watch(userPlaylistsProvider);
  final tracksByPlaylist = ref.watch(localPlaylistTracksProvider);

  return playlists
      .where((playlist) {
        final tracks = tracksByPlaylist[playlist.id] ?? const <DeezerTrack>[];
        return tracks.any((track) => track.id == trackId);
      })
      .toList(growable: false);
});
