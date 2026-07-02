import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/deezer_providers.dart';
import '../../core/api/models/deezer_album.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/content_cards.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer.dart';
import '../../widgets/snap_horizontal_list.dart';

/// Discover tab with three custom sub-tabs.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return ColoredBox(
      color: theme.background,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Text(
              'Discover',
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
          ),
          _SubTabs(
            labels: const <String>['New music', 'Charts'],
            active: _tab,
            onTap: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: theme.normalDuration,
              switchInCurve: theme.defaultCurve,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: switch (_tab) {
                0 => const KeyedSubtree(
                    key: ValueKey<String>('new'),
                    child: _NewMusicTab(),
                  ),
                _ => const KeyedSubtree(
                    key: ValueKey<String>('charts'),
                    child: _ChartsTab(),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom sub-tab strip — replaces TabBar entirely (forbidden in spec).
class _SubTabs extends StatelessWidget {
  const _SubTabs({
    required this.labels,
    required this.active,
    required this.onTap,
  });

  final List<String> labels;
  final int active;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: theme.fastDuration,
                  curve: theme.defaultCurve,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: active == i ? theme.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      theme.cardRadius == 0 ? 0 : 999,
                    ),
                    border: Border.all(
                      color: active == i
                          ? theme.accent
                          : theme.onSurface.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: active == i ? theme.background : theme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NewMusicTab extends ConsumerWidget {
  const _NewMusicTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(newReleasesProvider);
    return async.when(
      data: (albums) {
        if (albums.isEmpty) return const SizedBox.shrink();
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(child: _Hero(album: albums.first)),
            const SliverToBoxAdapter(
              child: SectionHeader(title: 'Fresh drops'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.74,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => AlbumCard(
                    album: albums[i + 1],
                    size: double.infinity,
                  ),
                  childCount: albums.length - 1,
                ),
              ),
            ),
          ],
        );
      },
      loading: () => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: <Widget>[
          const SizedBox(height: 12),
          const ShimmerBox(
            width: double.infinity,
            height: 200,
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < 4; i++) ...<Widget>[
            const ShimmerBox(
              width: double.infinity,
              height: 80,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.album});

  final DeezerAlbum album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final art = album.coverXl ?? album.coverBig ?? album.coverMedium;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(AppRoutes.albumPath(album.id)),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        height: 200,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 16),
          color: theme.surface,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (art != null)
              CachedNetworkImage(
                imageUrl: art,
                fit: BoxFit.cover,
                placeholder: (_, _) => ColoredBox(color: theme.surface),
                errorWidget: (_, _, _) => ColoredBox(color: theme.surface),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.7),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                    'NEW THIS WEEK',
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    album.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    album.artist?.name ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIconsFill.play,
                  color: theme.background,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ChartsTab extends ConsumerWidget {
  const _ChartsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(chartTracksProvider);
    final albums = ref.watch(chartAlbumsProvider);
    final lists = ref.watch(chartPlaylistsProvider);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        tracks.when(
          data: (list) {
            final top = list.take(50).toList();
            if (top.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
            return SliverToBoxAdapter(
              child: Column(
                children: <Widget>[
                  const SectionHeader(title: 'Top 50 tracks'),
                  for (var i = 0; i < top.length; i++)
                    TrackRow(
                      track: top[i],
                      queue: top,
                      indexInQueue: i,
                      showRank: true,
                    ),
                ],
              ),
            );
          },
          loading: () => const SliverToBoxAdapter(
            child: Column(
              children: [
                SectionHeader(title: 'Top 50 tracks'),
                _LoadingRows(),
              ],
            ),
          ),
          error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
        ),
        albums.when(
          data: (list) {
            if (list.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
            return SliverToBoxAdapter(
              child: Column(
                children: [
                  const SectionHeader(title: 'Top albums'),
                  SnapHorizontalList(
                    itemCount: list.length,
                    itemExtent: 150,
                    height: 198,
                    itemBuilder: (_, i) => AlbumCard(album: list[i]),
                  ),
                ],
              ),
            );
          },
          loading: () => const SliverToBoxAdapter(
            child: Column(
              children: [
                SectionHeader(title: 'Top albums'),
                SizedBox(height: 198),
              ],
            ),
          ),
          error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
        ),
        lists.when(
          data: (list) {
            if (list.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
            return SliverToBoxAdapter(
              child: Column(
                children: [
                  const SectionHeader(title: 'Top playlists'),
                  SnapHorizontalList(
                    itemCount: list.length,
                    itemExtent: 150,
                    height: 198,
                    itemBuilder: (_, i) => PlaylistCard(playlist: list[i]),
                  ),
                ],
              ),
            );
          },
          loading: () => const SliverToBoxAdapter(
            child: Column(
              children: [
                SectionHeader(title: 'Top playlists'),
                SizedBox(height: 198),
              ],
            ),
          ),
          error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (var i = 0; i < 6; i++)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: ShimmerBox(
              width: double.infinity,
              height: 48,
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
          ),
      ],
    );
  }
}
