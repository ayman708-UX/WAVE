import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/deezer_providers.dart';
import '../../core/api/deezer_api_client.dart';
import '../../core/api/models/deezer_album.dart';
import '../../core/api/models/deezer_artist.dart';
import '../../core/api/models/deezer_playlist.dart';
import '../../core/audio/player_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/recently_played.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_logger.dart';
import '../../services/app_updater_service.dart';
import '../../widgets/content_cards.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer.dart';
import '../../widgets/snap_horizontal_list.dart';
import '../../widgets/update_dialog.dart';
import '../../core/api/lastfm_providers.dart';
import '../../core/api/models/deezer_track.dart';
/// Home tab — 9 sections per spec:
///  1. Greeting + settings entry
///  2. Quick resume strip (recently played)
///  3. Trending tracks (top 10)
///  4. Made for you (chart playlists)
///  5. New releases (editorial selection albums)
///  6. Top artists (chart artists)
///  7. Mixes (chart playlists alt slice)
///  8. Editorial picks (chart albums)
///  9. Recently played (full)
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();
      if (updateInfo != null && mounted) {
        showDialog(
          context: context,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      }
    } catch (e) {
      appLogger.e('Failed to check for updates on startup', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return ColoredBox(
      color: theme.background,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(child: _Greeting()),
          const SliverToBoxAdapter(child: _QuickResumeSection()),
          const SliverToBoxAdapter(child: _TrendingSection()),
          const SliverToBoxAdapter(child: _MadeForYouSection()),
          const SliverToBoxAdapter(child: _NewReleasesSection()),
          const SliverToBoxAdapter(child: _TopArtistsSection()),
          const SliverToBoxAdapter(child: _MixesSection()),
          const SliverToBoxAdapter(child: _EditorialPicksSection()),
          const SliverToBoxAdapter(child: _RecentlyPlayedSection()),
          const SliverToBoxAdapter(child: _RecommendedTracksSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? 'Late night listen'
        : hour < 12
            ? 'Good morning'
            : hour < 18
                ? 'Good afternoon'
                : 'Good evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  greeting.toUpperCase(),
                  style: TextStyle(
                    color: theme.onSurfaceMuted,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'WAVE',
                  style: TextStyle(
                    color: theme.onSurface,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push(AppRoutes.settings),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.onSurface.withValues(alpha: 0.08),
                ),
              ),
              child: Icon(
                PhosphorIconsRegular.gear,
                color: theme.onSurface,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _QuickResumeSection extends ConsumerWidget {
  const _QuickResumeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(recentlyPlayedProvider).take(6).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          for (final e in entries)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openRecent(context, ref, e),
              onLongPressStart: (details) =>
                  _showRemoveMenu(context, ref, e, details.globalPosition),
              child: Container(
                width: (MediaQuery.of(context).size.width - 50) / 2,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(
                    theme.cardRadius == 0 ? 0 : 8,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(
                          theme.cardRadius == 0 ? 0 : 8,
                        ),
                        bottomLeft: Radius.circular(
                          theme.cardRadius == 0 ? 0 : 8,
                        ),
                      ),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: e.imageUrl != null && e.imageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: e.imageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => ColoredBox(
                                  color: theme.background,
                                ),
                                errorWidget: (_, _, _) =>
                                    ColoredBox(color: theme.background),
                              )
                            : ColoredBox(color: theme.background),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TrendingSection extends ConsumerWidget {
  const _TrendingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chartTracksProvider);
    return async.when(
      data: (tracks) {
        final top = tracks.take(10).toList();
        if (top.isEmpty) return const SizedBox.shrink();
        return Column(
          children: <Widget>[
            const SectionHeader(title: 'Trending now'),
            for (var i = 0; i < top.length; i++)
              TrackRow(
                track: top[i],
                queue: top,
                indexInQueue: i,
                showRank: true,
              ),
          ],
        );
      },
      loading: () => Column(
        children: const <Widget>[
          SectionHeader(title: 'Trending now'),
          _RowShimmer(),
        ],
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------

class _MadeForYouSection extends ConsumerWidget {
  const _MadeForYouSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(madeForYouAlbumsProvider);
    return async.when(
      data: (albums) {
        final top = albums.take(12).toList();
        if (top.isEmpty) return const SizedBox.shrink();
        return Column(
          children: <Widget>[
            const SectionHeader(title: 'Made for you'),
            _CoverRow<DeezerAlbum>(
              items: top,
              builder: (a) => AlbumCard(album: a),
            ),
          ],
        );
      },
      loading: () => Column(
        children: const <Widget>[
          SectionHeader(title: 'Made for you'),
          _CoverRowShimmer(),
        ],
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------

class _NewReleasesSection extends ConsumerWidget {
  const _NewReleasesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(newReleasesProvider);
    return async.when(
      data: (albums) {
        final top = albums.take(12).toList();
        if (top.isEmpty) return const SizedBox.shrink();
        return Column(
          children: <Widget>[
            const SectionHeader(title: 'New releases'),
            _CoverRow<DeezerAlbum>(
              items: top,
              builder: (a) => AlbumCard(album: a),
            ),
          ],
        );
      },
      loading: () => Column(
        children: const <Widget>[
          SectionHeader(title: 'New releases'),
          _CoverRowShimmer(),
        ],
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------

class _TopArtistsSection extends ConsumerWidget {
  const _TopArtistsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chartArtistsProvider);
    return async.when(
      data: (artists) {
        final top = artists.take(12).toList();
        if (top.isEmpty) return const SizedBox.shrink();
        return Column(
          children: <Widget>[
            const SectionHeader(title: 'Top artists'),
            _CoverRow<DeezerArtist>(
              items: top,
              itemSize: 110,
              builder: (a) => ArtistCircle(artist: a),
            ),
          ],
        );
      },
      loading: () => Column(
        children: const <Widget>[
          SectionHeader(title: 'Top artists'),
          _CoverRowShimmer(circle: true),
        ],
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------

class _MixesSection extends ConsumerWidget {
  const _MixesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chartPlaylistsProvider);
    return async.when(
      data: (lists) {
        final mixes = lists.length > 6
            ? lists.sublist(6, lists.length.clamp(6, 18))
            : lists;
        if (mixes.isEmpty) return const SizedBox.shrink();
        return Column(
          children: <Widget>[
            const SectionHeader(title: 'Mixes'),
            _CoverRow<DeezerPlaylist>(
              items: mixes,
              builder: (p) => PlaylistCard(playlist: p),
            ),
          ],
        );
      },
      loading: () => Column(
        children: const <Widget>[
          SectionHeader(title: 'Mixes'),
          _CoverRowShimmer(),
        ],
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------

class _EditorialPicksSection extends ConsumerWidget {
  const _EditorialPicksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chartAlbumsProvider);
    return async.when(
      data: (albums) {
        final top = albums.take(12).toList();
        if (top.isEmpty) return const SizedBox.shrink();
        return Column(
          children: <Widget>[
            const SectionHeader(title: 'Editorial picks'),
            _CoverRow<DeezerAlbum>(
              items: top,
              builder: (a) => AlbumCard(album: a),
            ),
          ],
        );
      },
      loading: () => Column(
        children: const <Widget>[
          SectionHeader(title: 'Editorial picks'),
          _CoverRowShimmer(),
        ],
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------

class _RecentlyPlayedSection extends ConsumerWidget {
  const _RecentlyPlayedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(recentlyPlayedProvider);
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = AppThemeScope.of(context);
    return Column(
      children: <Widget>[
        const SectionHeader(title: 'Recently played'),
        SnapHorizontalList(
          itemCount: entries.length,
          itemExtent: 120,
          height: 180,
          itemBuilder: (context, i) {
            final e = entries[i];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openRecent(context, ref, e),
              onLongPressStart: (details) =>
                  _showRemoveMenu(context, ref, e, details.globalPosition),
              child: SizedBox(
                width: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        e.kind == 'artist' ? 60 : theme.cardRadius,
                      ),
                      child: SizedBox(
                        width: 120,
                        height: 120,
                        child: e.imageUrl != null && e.imageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: e.imageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, _) =>
                                    ColoredBox(color: theme.surface),
                                errorWidget: (_, _, _) =>
                                    ColoredBox(color: theme.surface),
                              )
                            : ColoredBox(color: theme.surface),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      e.kind.toUpperCase(),
                      style: TextStyle(
                        color: theme.onSurfaceMuted,
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _RecommendedTracksSection extends ConsumerWidget {
  const _RecommendedTracksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recommendedTracksProvider);
    return async.when(
      data: (tracks) {
        final top = tracks.toList();
        if (top.isEmpty) return const SizedBox.shrink();
        return Column(
          children: <Widget>[
            const SectionHeader(title: 'Recommended tracks'),
            _CoverRow<DeezerTrack>(
              items: top,
              builder: (t) => TrackCard(track: t, queue: top),
            ),
          ],
        );
      },
      loading: () => Column(
        children: const <Widget>[
          SectionHeader(title: 'Recommended tracks'),
          _CoverRowShimmer(),
        ],
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers ------------------------------------------------------------------

void _openRecent(BuildContext context, WidgetRef ref, RecentEntry e) async {
  switch (e.kind) {
    case 'album':
      context.push(AppRoutes.albumPath(e.id));
      break;
    case 'playlist':
      context.push(AppRoutes.playlistPath(e.id));
      break;
    case 'artist':
      context.push(AppRoutes.artistPath(e.id));
      break;
    default:
      try {
        final track = await ref.read(deezerApiClientProvider).getTrack(e.id);
        await ref.read(playerControlsProvider).playTracks([track]);
        if (context.mounted) {
          context.push(AppRoutes.nowPlaying);
        }
      } catch (err) {
        appLogger.e('Failed to play recently played track: $err');
      }
  }
}

Future<void> _showRemoveMenu(
  BuildContext context,
  WidgetRef ref,
  RecentEntry e,
  Offset origin,
) async {
  await showWaveContextMenu(
    context: context,
    origin: origin,
    items: [
      ContextMenuItem(
        icon: PhosphorIconsRegular.trash,
        label: 'Remove from recently played',
        destructive: true,
        onTap: () => ref.read(recentlyPlayedProvider.notifier).remove(e),
      ),
    ],
  );
}

class _CoverRow<T> extends StatelessWidget {
  const _CoverRow({
    super.key,
    required this.items,
    required this.builder,
    this.itemSize = 150,
  });

  final List<T> items;
  final Widget Function(T item) builder;
  final double itemSize;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SnapHorizontalList(
      itemCount: items.length,
      itemExtent: itemSize,
      height: itemSize + 48,
      itemBuilder: (context, i) => builder(items[i]),
    );
  }
}

class _CoverRowShimmer extends StatelessWidget {
  const _CoverRowShimmer({this.circle = false});

  final bool circle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 198,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, _) => SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              circle
                  ? const ShimmerCircle(size: 110)
                  : const ShimmerSquare(size: 150),
              const SizedBox(height: 10),
              const ShimmerBox(width: 110, height: 11),
              const SizedBox(height: 6),
              const ShimmerBox(width: 70, height: 9),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowShimmer extends StatelessWidget {
  const _RowShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: <Widget>[
                const ShimmerSquare(size: 48, radius: 6),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const <Widget>[
                      ShimmerBox(width: 180, height: 12),
                      SizedBox(height: 6),
                      ShimmerBox(width: 100, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
