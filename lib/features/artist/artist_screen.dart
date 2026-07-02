import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/deezer_providers.dart';
import '../../core/api/models/deezer_album.dart';
import '../../core/api/models/deezer_artist.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/audio/player_providers.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/download_providers.dart';
import '../../core/downloads/download_status.dart';
import '../../core/storage/library_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/content_cards.dart';
import '../../widgets/detail_track_row.dart';
import '../../widgets/inline_error.dart';
import '../../widgets/play_shuffle_pair.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer.dart';

enum _ArtistTab { popular, discography, related, about }

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({super.key, required this.artistId});
  final int artistId;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  _ArtistTab _tab = _ArtistTab.popular;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final asyncArtist = ref.watch(artistProvider(widget.artistId));
    return Scaffold(
      backgroundColor: theme.background,
      body: asyncArtist.when(
        loading: () => const Center(child: ShimmerCircle(size: 80)),
        error: (e, _) => SafeArea(
          child: Center(
            child: InlineError(
              message: 'Could not load artist',
              onRetry: () => ref.invalidate(artistProvider(widget.artistId)),
            ),
          ),
        ),
        data: (artist) => _build(theme, artist),
      ),
    );
  }

  Widget _build(AppTheme theme, DeezerArtist artist) {
    final url = artist.pictureXl ?? artist.pictureBig ?? artist.picture;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: 320,
          backgroundColor: theme.background,
          elevation: 0,
          pinned: true,
          leading: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(PhosphorIconsRegular.caretLeft,
                  color: Colors.white, size: 20),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 68),
            title: Text(
              artist.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                shadows: [Shadow(blurRadius: 12, color: Colors.black54)],
              ),
            ),
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null)
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => ColoredBox(color: theme.surface),
                  )
                else
                  ColoredBox(color: theme.surface),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                      stops: [0.4, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              color: theme.background,
              child: _TabStrip(
                active: _tab,
                onSelect: (t) => setState(() => _tab = t),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatFans(artist.nbFan),
                  style: TextStyle(
                    color: theme.onSurfaceMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _ActionRow(artist: artist),
              ],
            ),
          ),
        ),
        _SliverTabContent(
          artistId: widget.artistId,
          tab: _tab,
          artist: artist,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _SliverTabContent extends ConsumerWidget {
  const _SliverTabContent({
    required this.artistId,
    required this.tab,
    required this.artist,
  });

  final int artistId;
  final _ArtistTab tab;
  final DeezerArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (tab) {
      _ArtistTab.popular => _PopularSliverList(artistId: artistId),
      _ArtistTab.discography => _DiscographySliverGrid(artistId: artistId),
      _ArtistTab.related => _RelatedSliverGrid(artistId: artistId),
      _ArtistTab.about => SliverToBoxAdapter(child: _About(artist: artist)),
    };
  }
}

class _PopularSliverList extends ConsumerWidget {
  const _PopularSliverList({required this.artistId});
  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTracks = ref.watch(artistTopTracksProvider(artistId));
    return asyncTracks.when(
      loading: () => SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: ShimmerBox(
              width: MediaQuery.of(context).size.width - 40,
              height: 48,
            ),
          ),
          childCount: 6,
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: InlineError(
            message: 'Could not load tracks',
            onRetry: () => ref.invalidate(artistTopTracksProvider(artistId)),
          ),
        ),
      ),
      data: (tracks) {
        final top = tracks.take(10).toList(growable: false);
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => DetailTrackRow(
              track: top[i],
              queue: top,
              indexInQueue: i,
              position: i + 1,
            ),
            childCount: top.length,
          ),
        );
      },
    );
  }
}

class _DiscographySliverGrid extends ConsumerWidget {
  const _DiscographySliverGrid({required this.artistId});
  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAlbums = ref.watch(artistAlbumsProvider(artistId));
    return asyncAlbums.when(
      loading: () => SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: List<Widget>.generate(
            4,
            (_) => const ShimmerSquare(size: 160),
          ),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: InlineError(
            message: 'Could not load discography',
            onRetry: () => ref.invalidate(artistAlbumsProvider(artistId)),
          ),
        ),
      ),
      data: (albums) {
        final sorted = <DeezerAlbum>[...albums]
          ..sort((a, b) =>
              (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.74,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => AlbumCard(album: sorted[i]),
              childCount: sorted.length,
            ),
          ),
        );
      },
    );
  }
}

class _RelatedSliverGrid extends ConsumerWidget {
  const _RelatedSliverGrid({required this.artistId});
  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRel = ref.watch(relatedArtistsProvider(artistId));
    return asyncRel.when(
      loading: () => SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid.count(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: List<Widget>.generate(
              6, (_) => const ShimmerCircle(size: 90)),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: InlineError(
            message: 'Could not load related artists',
            onRetry: () => ref.invalidate(relatedArtistsProvider(artistId)),
          ),
        ),
      ),
      data: (artists) => SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.70,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => ArtistCircle(artist: artists[i]),
            childCount: artists.length,
          ),
        ),
      ),
    );
  }
}

String _formatFans(int? fans) {
  if (fans == null || fans <= 0) return 'Artist';
  if (fans >= 1000000) {
    final m = (fans / 1000000);
    return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M monthly listeners';
  }
  if (fans >= 1000) {
    final k = fans / 1000;
    return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}K monthly listeners';
  }
  return '$fans monthly listeners';
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.artist});
  final DeezerArtist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final following =
        ref.watch(followedArtistsProvider).any((a) => a.id == artist.id);
    final topAsync = ref.watch(artistTopTracksProvider(artist.id));
    final popularTracks = topAsync.maybeWhen(
      data: (t) => t.take(10).toList(growable: false),
      orElse: () => const <DeezerTrack>[],
    );
    final popularCoverage = downloadCoverageForTracks(
      popularTracks,
      ref.watch(downloadedTracksProvider),
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: PlayShufflePair(
            onPlay: () {
              final tracks = topAsync.maybeWhen(
                data: (t) => t,
                orElse: () => const <DeezerTrack>[],
              );
              if (tracks.isNotEmpty) {
                ref.read(playerControlsProvider).playTracks(tracks);
              }
            },
            onShuffle: () async {
              final tracks = topAsync.maybeWhen(
                data: (t) => t,
                orElse: () => const <DeezerTrack>[],
              );
              if (tracks.isEmpty) return;
              final controls = ref.read(playerControlsProvider);
              await controls.setShuffle(true);
              await controls.playTracks(tracks);
            },
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!popularCoverage.hasTracks) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Popular tracks are still loading'),
                ),
              );
              return;
            }
            if (popularCoverage.allOnDevice) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Popular tracks are already on device: ${artist.name}'),
                ),
              );
              return;
            }

            ref.read(downloadManagerProvider).queueTracks(
                  popularCoverage.missingTracks,
                  title: popularCoverage.partiallyOnDevice
                      ? 'Missing popular tracks: ${artist.name}'
                      : 'Popular: ${artist.name}',
                  replaceFinishedQueue: false,
                );

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  popularCoverage.partiallyOnDevice
                      ? 'Queued ${popularCoverage.missing} missing popular tracks: ${artist.name}'
                      : 'Queued popular tracks: ${artist.name}',
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(
                  theme.cardRadius == 0 ? 0 : 999),
              border: Border.all(
                color: popularCoverage.allOnDevice
                    ? theme.accent
                    : theme.onSurface.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              popularCoverage.allOnDevice
                  ? PhosphorIconsFill.cloudCheck
                  : PhosphorIconsRegular.cloudArrowDown,
              color: popularCoverage.allOnDevice ? theme.accent : theme.onSurface,
              size: 16,
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              ref.read(followedArtistsProvider.notifier).toggle(artist),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: following ? theme.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(
                  theme.cardRadius == 0 ? 0 : 999),
              border: Border.all(
                color: following
                    ? theme.accent
                    : theme.onSurface.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              following ? 'FOLLOWING' : 'FOLLOW',
              style: TextStyle(
                color: following ? theme.background : theme.onSurface,
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.active, required this.onSelect});
  final _ArtistTab active;
  final ValueChanged<_ArtistTab> onSelect;

  static const Map<_ArtistTab, String> _labels = <_ArtistTab, String>{
    _ArtistTab.popular: 'POPULAR',
    _ArtistTab.discography: 'DISCOGRAPHY',
    _ArtistTab.related: 'RELATED',
    _ArtistTab.about: 'ABOUT',
  };

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: _labels.entries.map((e) {
          final isActive = e.key == active;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(right: 18),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.accent
                    : theme.onSurface.withValues(alpha: 0.06),
                borderRadius:
                    BorderRadius.circular(theme.cardRadius == 0 ? 0 : 999),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                  color: isActive ? theme.background : theme.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About({required this.artist});
  final DeezerArtist artist;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'About'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              artist.name,
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${artist.nbAlbum ?? 0} albums  ·  ${_formatFans(artist.nbFan)}',
              style: TextStyle(
                color: theme.onSurfaceMuted,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
