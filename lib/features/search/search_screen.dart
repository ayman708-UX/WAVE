import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/storage/search_providers.dart';
import '../../core/api/deezer_api_client.dart';
import '../../core/api/lastfm_providers.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/audio/player_providers.dart';
import '../../core/auth/community_playlists_provider.dart';
import '../../core/auth/supabase_profile_service.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/recently_played.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/community_playlist_card.dart';
import '../../widgets/content_cards.dart';
import '../../widgets/inline_error.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer.dart';
import '../../widgets/snap_horizontal_list.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted && _isFocused != _focus.hasFocus) {
        setState(() => _isFocused = _focus.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String value) {
    final t = value.trim();
    if (t.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).push(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final query = ref.watch(searchQueryProvider);
    final hasQuery = query.isNotEmpty;
    return ColoredBox(
      color: theme.background,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: hasQuery
                  ? const _Results()
                  : _Browse(
                      onTapRecent: (q) {
                        _ctrl.text = q;
                        ref.read(searchQueryProvider.notifier).setText(q);
                      },
                    ),
            ),
            // Backdrop blur appears when focused but no query yet.
            if (_isFocused && !hasQuery)
              Positioned.fill(
                top: 80,
                child: IgnorePointer(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      color: theme.background.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: WaveSearchBar(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: (v) =>
                    ref.read(searchQueryProvider.notifier).setText(v),
                onSubmitted: _commit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Browse (idle state) -----------------------------------------------------

class _Browse extends ConsumerWidget {
  const _Browse({required this.onTapRecent});

  final ValueChanged<String> onTapRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        if (recents.isNotEmpty) ...<Widget>[
          const SliverToBoxAdapter(child: SectionHeader(title: 'Recent')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final q in recents)
                    RecentSearchChip(
                      label: q,
                      onTap: () => onTapRecent(q),
                      onRemove: () =>
                          ref.read(recentSearchesProvider.notifier).remove(q),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Results (active query) --------------------------------------------------

class _Results extends ConsumerStatefulWidget {
  const _Results();

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final async = ref.watch(searchResultsProvider);
    return async.when(
      loading: () => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: <Widget>[
          for (var i = 0; i < 5; i++) ...<Widget>[
            const ShimmerBox(
              width: double.infinity,
              height: 56,
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
      error: (e, _) => InlineError(
        message: 'Search failed. Tap retry.',
        onRetry: () => ref.invalidate(searchResultsProvider),
      ),
      data: (r) {
        if (r.isEmpty) {
          return _EmptyState(theme: theme);
        }

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            // WAVE Users section (from Supabase)
            SliverToBoxAdapter(
              child: _WaveUsersSection(query: ref.watch(searchQueryProvider)),
            ),
            // Community Playlists section (from Supabase)
            SliverToBoxAdapter(
              child: _CommunityPlaylistsSearchSection(
                query: ref.watch(searchQueryProvider),
              ),
            ),
            if (r.tracks.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(child: SectionHeader(title: 'Tracks')),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final track = r.tracks[i];
                  return TrackRow(
                    track: track,
                    queue: r.tracks,
                    indexInQueue: i,
                    onTapOverride: () async => _playSearchTrack(
                      context,
                      ref,
                      track,
                      r.tracks,
                      i,
                      addRelated: true,
                    ),
                  );
                }, childCount: r.tracks.length > 5 ? 5 : r.tracks.length),
              ),
            ],
            if (r.artists.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(child: SectionHeader(title: 'Artists')),
              SliverToBoxAdapter(
                child: SnapHorizontalList(
                  itemCount: r.artists.length,
                  itemExtent: 110,
                  height: 158,
                  itemBuilder: (_, i) => ArtistCircle(artist: r.artists[i]),
                ),
              ),
            ],
            if (r.albums.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(child: SectionHeader(title: 'Albums')),
              SliverToBoxAdapter(
                child: SnapHorizontalList(
                  itemCount: r.albums.length,
                  itemExtent: 150,
                  height: 198,
                  itemBuilder: (_, i) => AlbumCard(album: r.albums[i]),
                ),
              ),
            ],
            if (r.playlists.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(
                child: SectionHeader(title: 'Playlists'),
              ),
              SliverToBoxAdapter(
                child: SnapHorizontalList(
                  itemCount: r.playlists.length,
                  itemExtent: 150,
                  height: 198,
                  itemBuilder: (_, i) => PlaylistCard(playlist: r.playlists[i]),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }

  Future<void> _playSearchTrack(
    BuildContext context,
    WidgetRef ref,
    DeezerTrack track,
    List<DeezerTrack> queue,
    int index, {
    required bool addRelated,
  }) async {
    final controls = ref.read(playerControlsProvider);
    await controls.playTracks(queue, startIndex: index);

    if (context.mounted) {
      ref
          .read(recentlyPlayedProvider.notifier)
          .push(
            RecentEntry(
              kind: 'track',
              id: track.id,
              title: track.title,
              subtitle: track.artist?.name,
              imageUrl: track.album?.coverMedium ?? track.album?.cover,
              atMillis: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    }

    if (!addRelated || _isYoutubeListing(track)) return;

    final artistName = track.artist?.name;
    if (artistName == null || artistName.isEmpty) return;

    final lastfmApi = ref.read(lastfmApiClientProvider);
    try {
      final similar = await lastfmApi.getSimilarTracks(track.title, artistName);
      if (similar.isEmpty) return;

      final deezerApi = ref.read(deezerApiClientProvider);
      int added = 0;
      for (final t in similar) {
        final tName = t['name'] ?? '';
        final tArtist = t['artist'] ?? '';
        if (tName.isEmpty || tArtist.isEmpty) continue;

        try {
          final searchRes = await deezerApi.searchTracks(
            'artist:"$tArtist" track:"$tName"',
          );
          if (searchRes.isNotEmpty) {
            await controls.addToQueueLast(searchRes.first);
            added++;
            if (added >= 15) break; // Limit related tracks
          }
        } catch (_) {}
      }
    } catch (_) {
      // ignore errors silently
    }
  }

  bool _isYoutubeListing(DeezerTrack track) =>
      track.link?.startsWith('wave://youtube') == true || track.id < 0;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    final t = theme as AppTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: t.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: t.accent.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Icon(
              PhosphorIconsRegular.waveform,
              color: t.accent,
              size: 36,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No matches',
            style: TextStyle(
              color: t.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different artist, album or song.',
            style: TextStyle(color: t.onSurfaceMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// WAVE Users section -------------------------------------------------------

class _WaveUsersSection extends ConsumerStatefulWidget {
  const _WaveUsersSection({required this.query});
  final String query;

  @override
  ConsumerState<_WaveUsersSection> createState() => _WaveUsersSectionState();
}

class _WaveUsersSectionState extends ConsumerState<_WaveUsersSection> {
  List<Map<String, dynamic>> _users = [];
  bool _searched = false;

  @override
  void didUpdateWidget(_WaveUsersSection old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _search();
    }
  }

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    if (widget.query.trim().isEmpty) {
      setState(() {
        _users = [];
        _searched = false;
      });
      return;
    }
    final svc = ref.read(supabaseProfileProvider);
    final results = await svc.searchUsers(widget.query);
    if (mounted) {
      setState(() {
        _users = results;
        _searched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_searched || _users.isEmpty) return const SizedBox.shrink();
    final theme = AppThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'WAVE Users'),
        SnapHorizontalList(
          itemCount: _users.length,
          itemExtent: 180,
          height: 90,
          spacing: 10,
          itemBuilder: (context, i) {
            final user = _users[i];
            return _WaveUserCard(
              displayName: user['display_name'] ?? 'User',
              username: user['username'] ?? '',
              isPublic: user['is_public'] == true,
              theme: theme,
              onTap: () {
                final userId = user['id'] as String?;
                if (userId != null) {
                  context.push(AppRoutes.userProfilePath(userId));
                }
              },
            );
          },
        ),
      ],
    );
  }
}

class _WaveUserCard extends StatelessWidget {
  const _WaveUserCard({
    required this.displayName,
    required this.username,
    required this.isPublic,
    required this.theme,
    required this.onTap,
  });

  final String displayName;
  final String username;
  final bool isPublic;
  final AppTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.accent.withValues(alpha: 0.2),
                border: Border.all(color: theme.accent, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      color: theme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    style: TextStyle(color: theme.onSurfaceMuted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isPublic) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          PhosphorIconsRegular.lock,
                          size: 10,
                          color: theme.onSurfaceMuted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Private',
                          style: TextStyle(
                            color: theme.onSurfaceMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Community Playlists Search Section --------------------------------------

class _CommunityPlaylistsSearchSection extends ConsumerWidget {
  const _CommunityPlaylistsSearchSection({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) return const SizedBox.shrink();

    final asyncPlaylists = ref.watch(searchCommunityPlaylistsProvider(query));

    return asyncPlaylists.when(
      data: (playlists) {
        if (playlists.isEmpty) return const SizedBox.shrink();

        return Column(
          children: [
            const SectionHeader(title: 'Community Playlists'),
            SnapHorizontalList(
              itemCount: playlists.length,
              itemExtent: 150,
              height: 198,
              spacing: 12,
              itemBuilder: (context, i) => CommunityPlaylistCard(communityPlaylist: playlists[i]),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
