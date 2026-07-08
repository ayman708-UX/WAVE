import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/supabase_profile_service.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

/// Screen to view another WAVE user's public profile.
/// Shows their playlists and library if the account is public.
import '../../core/audio/player_providers.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/api/models/deezer_artist.dart';
import '../../core/api/models/deezer_album.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _playlists = [];
  Map<String, List<Map<String, dynamic>>> _library = {
    'tracks': [],
    'albums': [],
    'artists': [],
  };
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final svc = ref.read(supabaseProfileProvider);
    final profile = await svc.getProfile(widget.userId);
    if (!mounted) return;

    if (profile == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _profile = profile;
    });

    // Only load playlists/library if the account is public
    if (profile['is_public'] == true) {
      final playlists = await svc.getUserPlaylists(widget.userId);
      final library = await svc.getUserLibrary(widget.userId);
      if (mounted) {
        setState(() {
          _playlists = playlists;
          _library = library;
          _loading = false;
        });
      }
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.accent))
          : _profile == null
          ? _buildNotFound(theme)
          : RefreshIndicator(
              onRefresh: () async {
                await _loadProfile();
              },
              color: theme.accent,
              backgroundColor: theme.surface,
              child: CustomScrollView(
                slivers: [SliverFillRemaining(child: _buildProfile(theme))],
              ),
            ),
    );
  }

  Widget _buildNotFound(AppTheme theme) {
    return SafeArea(
      child: Column(
        children: [
          _buildAppBar(theme, 'User'),
          const Expanded(
            child: Center(
              child: Text('User not found', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
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
        ],
      ),
    );
  }

  Widget _buildProfile(AppTheme theme) {
    final displayName = _profile!['display_name'] ?? 'User';
    final username = _profile!['username'] ?? '';
    final isPublic = _profile!['is_public'] == true;

    return Column(
      children: [
        _buildAppBar(theme, displayName),
        const SizedBox(height: 16),

        // Avatar
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.accent.withValues(alpha: 0.2),
            border: Border.all(color: theme.accent, width: 2.5),
          ),
          alignment: Alignment.center,
          child: Text(
            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
            style: TextStyle(
              color: theme.accent,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Name
        Text(
          displayName,
          style: TextStyle(
            color: theme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '@$username',
          style: TextStyle(color: theme.onSurfaceMuted, fontSize: 14),
        ),
        const SizedBox(height: 6),

        // Public/Private badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isPublic
                ? theme.accent.withValues(alpha: 0.15)
                : theme.onSurfaceMuted.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPublic
                    ? PhosphorIconsRegular.globe
                    : PhosphorIconsRegular.lock,
                size: 13,
                color: isPublic ? theme.accent : theme.onSurfaceMuted,
              ),
              const SizedBox(width: 4),
              Text(
                isPublic ? 'Public' : 'Private',
                style: TextStyle(
                  color: isPublic ? theme.accent : theme.onSurfaceMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // If private, show private message
        if (!isPublic)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIconsRegular.lockKey,
                    size: 48,
                    color: theme.onSurfaceMuted.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This account is private',
                    style: TextStyle(
                      color: theme.onSurfaceMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Their playlists and library aren't visible",
                    style: TextStyle(
                      color: theme.onSurfaceMuted.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // If public, show tabs
        if (isPublic) ...[
          // Tab bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: theme.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: theme.background,
              unselectedLabelColor: theme.onSurfaceMuted,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerHeight: 0,
              padding: const EdgeInsets.all(3),
              tabs: const [
                Tab(text: 'Playlists'),
                Tab(text: 'Library'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _PlaylistsTab(playlists: _playlists, theme: theme),
                _LibraryTab(library: _library, theme: theme),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  final List<Map<String, dynamic>> playlists;
  final AppTheme theme;

  const _PlaylistsTab({required this.playlists, required this.theme});

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return Center(
        child: Text(
          'No playlists yet',
          style: TextStyle(color: theme.onSurfaceMuted, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        final name = playlist['name'] ?? 'Untitled';
        final isPublic = playlist['is_public'] == true;
        final songs = playlist['songs'] as List<dynamic>? ?? [];

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child:
                  songs.isNotEmpty &&
                      songs.first['cover_url'] != null &&
                      (songs.first['cover_url'] as String).isNotEmpty
                  ? Image.network(
                      songs.first['cover_url'] as String,
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _buildPlaylistFallback(isPublic, theme),
                    )
                  : _buildPlaylistFallback(isPublic, theme),
            ),
            title: Text(
              name,
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              isPublic ? '${songs.length} tracks' : 'Private playlist',
              style: TextStyle(color: theme.onSurfaceMuted, fontSize: 12),
            ),
            trailing: isPublic
                ? Icon(
                    PhosphorIconsRegular.caretRight,
                    color: theme.onSurfaceMuted,
                    size: 16,
                  )
                : null,
            onTap: isPublic
                ? () {
                    context.push(
                      AppRoutes.sharedPlaylistPath(playlist['id'].toString()),
                    );
                  }
                : null,
          ),
        );
      },
    );
  }

  Widget _buildPlaylistFallback(bool isPublic, AppTheme theme) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: isPublic
            ? theme.accent.withValues(alpha: 0.15)
            : theme.onSurfaceMuted.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(
        isPublic ? PhosphorIconsFill.musicNotesPlus : PhosphorIconsFill.lock,
        color: isPublic ? theme.accent : theme.onSurfaceMuted,
        size: 22,
      ),
    );
  }
}

class _LibraryTab extends ConsumerWidget {
  final Map<String, List<Map<String, dynamic>>> library;
  final AppTheme theme;

  const _LibraryTab({required this.library, required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = library['tracks'] ?? [];
    final albums = library['albums'] ?? [];
    final artists = library['artists'] ?? [];

    if (tracks.isEmpty && albums.isEmpty && artists.isEmpty) {
      return Center(
        child: Text(
          'Library is empty',
          style: TextStyle(color: theme.onSurfaceMuted, fontSize: 14),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        if (tracks.isNotEmpty) ...[
          _buildHeader('Liked Tracks'),
          _buildList(
            tracks,
            icon: PhosphorIconsRegular.musicNote,
            titleKey: 'title',
            subtitleKey: 'artist',
            itemKey: 'track_data',
            idKey: 'track_id',
          ),
        ],
        if (albums.isNotEmpty) ...[
          _buildHeader('Liked Albums'),
          _buildList(
            albums,
            icon: PhosphorIconsRegular.disc,
            titleKey: 'title',
            subtitleKey: 'artist',
            itemKey: 'album_data',
            idKey: 'album_id',
          ),
        ],
        if (artists.isNotEmpty) ...[
          _buildHeader('Following'),
          _buildList(
            artists,
            icon: PhosphorIconsRegular.microphoneStage,
            titleKey: 'name',
            subtitleKey: 'nb_fan',
            itemKey: 'artist_data',
            idKey: 'artist_id',
            isArtist: true,
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  Widget _buildHeader(String title) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      sliver: SliverToBoxAdapter(
        child: Text(
          title,
          style: TextStyle(
            color: theme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    List<Map<String, dynamic>> items, {
    required IconData icon,
    required String titleKey,
    required String subtitleKey,
    required String itemKey,
    required String idKey,
    bool isArtist = false,
  }) {
    return Consumer(
      builder: (context, ref, child) {
        return SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final entry = items[index];
            final data = entry[itemKey] as Map<String, dynamic>? ?? {};
            final title = data[titleKey]?.toString() ?? 'Unknown';

            String subtitle = '';
            if (isArtist) {
              final fans = data[subtitleKey] as int? ?? 0;
              subtitle = '$fans fans';
            } else {
              final subData = data[subtitleKey];
              if (subData is Map) {
                subtitle = subData['name']?.toString() ?? 'Unknown';
              } else {
                subtitle = subData?.toString() ?? 'Unknown';
              }
            }

            String? coverUrl;
            if (itemKey == 'track_data') {
              if (data['album'] is Map) {
                coverUrl =
                    data['album']['cover_medium'] ?? data['album']['cover'];
              }
            } else if (itemKey == 'album_data') {
              coverUrl = data['cover_medium'] ?? data['cover'];
            } else if (itemKey == 'artist_data') {
              coverUrl = data['picture_medium'] ?? data['picture'];
            }

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(isArtist ? 99 : 8),
                  child: coverUrl != null && coverUrl.isNotEmpty
                      ? Image.network(
                          coverUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _placeholder(icon, isArtist),
                        )
                      : _placeholder(icon, isArtist),
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
                  subtitle,
                  style: TextStyle(color: theme.onSurfaceMuted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  final idStr = entry[idKey]?.toString();
                  if (idStr == null) return;
                  final id = int.tryParse(idStr);
                  if (id == null) return;

                  if (isArtist) {
                    context.push(AppRoutes.artistPath(id));
                  } else if (idKey == 'album_id') {
                    context.push(AppRoutes.albumPath(id));
                  } else if (idKey == 'track_id') {
                    final tracks = items.map((i) {
                      final data = i[itemKey] as Map<String, dynamic>? ?? {};
                      return DeezerTrack(
                        id: data['id'] ?? 0,
                        title: data['title'] ?? 'Unknown',
                        duration: data['duration'] ?? 0,
                        artist: DeezerArtist(
                          id: data['artist'] is Map
                              ? (data['artist']['id'] ?? 0)
                              : 0,
                          name: data['artist'] is Map
                              ? (data['artist']['name'] ?? 'Unknown')
                              : (data['artist']?.toString() ?? 'Unknown'),
                        ),
                        album: DeezerAlbum(
                          id: data['album'] is Map
                              ? (data['album']['id'] ?? 0)
                              : 0,
                          title: data['album'] is Map
                              ? (data['album']['title'] ?? '')
                              : '',
                          coverMedium:
                              data['cover_url'] ??
                              (data['album'] is Map
                                  ? data['album']['cover_medium']
                                  : null),
                        ),
                      );
                    }).toList();
                    final idx = items.indexOf(entry);
                    ref
                        .read(playerControlsProvider)
                        .playTracks(tracks, startIndex: idx);
                  }
                },
              ),
            );
          }, childCount: items.length),
        );
      },
    );
  }

  Widget _placeholder(IconData icon, bool isArtist) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(isArtist ? 99 : 8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: theme.onSurfaceMuted, size: 20),
    );
  }
}
