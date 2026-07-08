import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/supabase_profile_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/library_providers.dart';
import '../../core/audio/player_providers.dart';
import '../../core/api/models/deezer_playlist.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/api/models/deezer_user.dart';
import '../../core/api/models/deezer_artist.dart';
import '../../core/api/models/deezer_album.dart';

/// Screen to view a shared playlist fetched from Supabase by its UUID.
class SharedPlaylistScreen extends ConsumerStatefulWidget {
  final String playlistId;
  const SharedPlaylistScreen({super.key, required this.playlistId});

  @override
  ConsumerState<SharedPlaylistScreen> createState() =>
      _SharedPlaylistScreenState();
}

class _SharedPlaylistScreenState extends ConsumerState<SharedPlaylistScreen> {
  Map<String, dynamic>? _playlist;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(supabaseProfileProvider);
    final pl = await svc.getPlaylistById(widget.playlistId);
    if (mounted) {
      setState(() {
        _playlist = pl;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: theme.accent))
            : _playlist == null
                ? _buildNotFound(theme)
                : _buildPlaylist(theme),
      ),
    );
  }

  Widget _buildNotFound(AppTheme theme) {
    return Column(
      children: [
        _buildAppBar(theme, 'Playlist'),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsRegular.magnifyingGlass,
                  size: 48,
                  color: theme.onSurfaceMuted.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Playlist not found',
                  style: TextStyle(
                    color: theme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Check the ID and try again',
                  style: TextStyle(
                    color: theme.onSurfaceMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar(AppTheme theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(PhosphorIconsRegular.caretLeft, color: theme.onSurface),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Consumer(
            builder: (context, ref, child) {
              final isSaved = ref.watch(likedPlaylistsProvider).any((p) => p.title == title);
              
              return IconButton(
                icon: Icon(
                  isSaved ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                  color: isSaved ? theme.accent : theme.onSurfaceMuted,
                ),
                onPressed: () {
                  final playlistId = _playlist!['id'].hashCode;
                  final internalId = playlistId < 0 ? playlistId : -playlistId;
                  
                  final songs = _playlist!['songs'] as List<dynamic>? ?? [];
                  final pictureUrl = songs.isNotEmpty ? songs.first['cover_url'] as String? : null;
                  
                  final dp = DeezerPlaylist(
                    id: internalId,
                    title: title,
                    description: _playlist!['description'] as String? ?? '',
                    public: true,
                    nbTracks: songs.length,
                    picture: pictureUrl,
                    pictureMedium: pictureUrl,
                    pictureBig: pictureUrl,
                    creator: DeezerUser(id: 0, name: _playlist!['profiles']?['display_name'] ?? _playlist!['profiles']?['username'] ?? 'Community'),
                  );
                  final parsedTracks = songs.map((s) {
                    final song = s as Map<String, dynamic>;
                    return DeezerTrack(
                      id: song['id'] ?? 0,
                      title: song['title'] ?? 'Unknown',
                      duration: song['duration'] ?? 0,
                      artist: DeezerArtist(id: 0, name: song['artist'] ?? 'Unknown'),
                      album: DeezerAlbum(id: 0, title: '', coverMedium: song['cover_url']),
                    );
                  }).toList();
                  
                  ref.read(likedPlaylistsProvider.notifier).toggle(dp);
                  if (!isSaved) {
                    // Save tracks so they can be loaded if opened from Library -> Liked Playlists
                    ref.read(localPlaylistTracksProvider.notifier).addTracks(internalId, parsedTracks);
                  }
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isSaved ? 'Removed from Liked Playlists' : 'Saved to Liked Playlists')),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylist(AppTheme theme) {
    final name = _playlist!['name'] ?? 'Untitled';
    final description = _playlist!['description'] as String? ?? '';
    final songs = _playlist!['songs'] as List<dynamic>? ?? [];
    final profile = _playlist!['profiles'] as Map<String, dynamic>? ?? {};
    final creator = profile['display_name'] ?? profile['username'] ?? 'User';

    final parsedTracks = songs.map((s) {
      final song = s as Map<String, dynamic>;
      return DeezerTrack(
        id: song['id'] ?? 0,
        title: song['title'] ?? 'Unknown',
        duration: song['duration'] ?? 0,
        artist: DeezerArtist(id: 0, name: song['artist'] ?? 'Unknown'),
        album: DeezerAlbum(id: 0, title: '', coverMedium: song['cover_url']),
      );
    }).toList();

    return Column(
      children: [
        _buildAppBar(theme, name),
        const SizedBox(height: 16),

        // Header
        Builder(
          builder: (context) {
            final firstCover = parsedTracks.isNotEmpty && parsedTracks.first.album?.coverMedium != null
                ? parsedTracks.first.album!.coverMedium!
                : null;
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: firstCover != null && firstCover.isNotEmpty
                  ? Image.network(
                      firstCover,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildHeaderFallback(theme),
                    )
                  : _buildHeaderFallback(theme),
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          name,
          style: TextStyle(
            color: theme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () {
            final userId = _playlist!['user_id'] as String?;
            if (userId != null) {
              context.push(AppRoutes.userProfilePath(userId));
            }
          },
          child: Text(
            'by $creator · ${songs.length} tracks',
            style: TextStyle(
              color: theme.onSurfaceMuted,
              fontSize: 13,
            ),
          ),
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              description,
              style: TextStyle(
                color: theme.onSurfaceMuted.withValues(alpha: 0.7),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const SizedBox(height: 20),

        // Song list
        Expanded(
          child: songs.isEmpty
              ? Center(
                  child: Text(
                    'This playlist is empty',
                    style: TextStyle(color: theme.onSurfaceMuted, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index] as Map<String, dynamic>? ?? {};
                    final title = song['title'] ?? 'Unknown';
                    final artist = song['artist'] ?? 'Unknown';
                    final coverUrl = song['cover_url'] as String?;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 2),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: coverUrl != null && coverUrl.isNotEmpty
                              ? Image.network(
                                  coverUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _placeholder(theme),
                                )
                              : _placeholder(theme),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            color: theme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          artist,
                          style: TextStyle(
                            color: theme.onSurfaceMuted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: theme.onSurfaceMuted.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          ref.read(playerControlsProvider).playTracks(parsedTracks, startIndex: index);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _placeholder(AppTheme theme) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(PhosphorIconsRegular.musicNote,
          color: theme.onSurfaceMuted, size: 20),
    );
  }

  Widget _buildHeaderFallback(AppTheme theme) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.accent.withValues(alpha: 0.3), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Icon(
        PhosphorIconsFill.playlist,
        color: theme.accent,
        size: 40,
      ),
    );
  }
}
