import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/deezer_providers.dart';
import '../../core/api/models/deezer_album.dart';
import '../../core/api/models/deezer_track.dart';
import '../../core/audio/player_providers.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/download_providers.dart';
import '../../core/downloads/download_status.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/library_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/content_cards.dart';
import '../../widgets/detail_track_row.dart';
import '../../widgets/inline_error.dart';
import '../../widgets/play_shuffle_pair.dart';
import '../../widgets/section_header.dart';
import '../../widgets/shimmer.dart';
import '../../widgets/snap_horizontal_list.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.albumId});
  final int albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final albumAsync = ref.watch(albumProvider(albumId));
    final tracksAsync = ref.watch(albumTracksProvider(albumId));
    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: albumAsync.when(
          loading: () => const _Loading(),
          error: (e, _) => Center(
            child: InlineError(
              message: 'Could not load album',
              onRetry: () => ref.invalidate(albumProvider(albumId)),
            ),
          ),
          data: (album) => _AlbumBody(
            album: album,
            tracksAsync: tracksAsync,
            onRetryTracks: () => ref.invalidate(albumTracksProvider(albumId)),
          ),
        ),
      ),
    );
  }
}

class _AlbumBody extends ConsumerWidget {
  const _AlbumBody({
    required this.album,
    required this.tracksAsync,
    required this.onRetryTracks,
  });

  final DeezerAlbum album;
  final AsyncValue<List<DeezerTrack>> tracksAsync;
  final VoidCallback onRetryTracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final saved = ref.watch(likedAlbumsProvider).any((a) => a.id == album.id);
    final downloadableTracks = tracksAsync.maybeWhen(
      data: (t) => t
          .map(
            (track) =>
                track.album == null ? track.copyWith(album: album) : track,
          )
          .toList(growable: false),
      orElse: () => const <DeezerTrack>[],
    );
    final albumCoverage = downloadCoverageForTracks(
      downloadableTracks,
      ref.watch(downloadedTracksProvider),
    );
    final cover =
        album.coverXl ?? album.coverBig ?? album.coverMedium ?? album.cover;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        SliverToBoxAdapter(child: _Header(theme: theme)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.65,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            theme.cardRadius == 0 ? 0 : 12,
                          ),
                          child: cover != null
                              ? CachedNetworkImage(
                                  imageUrl: cover,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) =>
                                      ColoredBox(color: theme.surface),
                                  errorWidget: (_, _, _) =>
                                      ColoredBox(color: theme.surface),
                                )
                              : ColoredBox(color: theme.surface),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  album.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final id = album.artist?.id;
                    if (id != null) context.push(AppRoutes.artistPath(id));
                  },
                  child: Text(
                    album.artist?.name ?? '',
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _meta(album),
                  style: TextStyle(color: theme.onSurfaceMuted, fontSize: 12),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: PlayShufflePair(
                        onPlay: () {
                          final tracks = tracksAsync.maybeWhen(
                            data: (t) => t,
                            orElse: () => const <DeezerTrack>[],
                          );
                          if (tracks.isNotEmpty) {
                            ref.read(playerControlsProvider).playTracks(tracks);
                          }
                        },
                        onShuffle: () async {
                          final tracks = tracksAsync.maybeWhen(
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
                      onTap: () =>
                          ref.read(likedAlbumsProvider.notifier).toggle(album),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            theme.cardRadius == 0 ? 0 : 999,
                          ),
                          border: Border.all(
                            color: saved
                                ? theme.accent
                                : theme.onSurface.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Icon(
                          saved
                              ? PhosphorIconsFill.heart
                              : PhosphorIconsRegular.heart,
                          color: saved ? theme.accent : theme.onSurface,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!albumCoverage.hasTracks) return;
                        if (albumCoverage.allOnDevice) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Album is already on device: ${album.title}',
                              ),
                            ),
                          );
                          return;
                        }
                        ref
                            .read(downloadManagerProvider)
                            .queueTracks(
                              albumCoverage.missingTracks,
                              title: albumCoverage.partiallyOnDevice
                                  ? 'Missing album tracks: ${album.title}'
                                  : 'Album: ${album.title}',
                              replaceFinishedQueue: false,
                            );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              albumCoverage.partiallyOnDevice
                                  ? 'Queued ${albumCoverage.missing} missing album tracks: ${album.title}'
                                  : 'Queued album download: ${album.title}',
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            theme.cardRadius == 0 ? 0 : 999,
                          ),
                          border: Border.all(
                            color: albumCoverage.allOnDevice
                                ? theme.accent
                                : theme.onSurface.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Icon(
                          albumCoverage.allOnDevice
                              ? PhosphorIconsFill.cloudCheck
                              : PhosphorIconsRegular.cloudArrowDown,
                          color: albumCoverage.allOnDevice
                              ? theme.accent
                              : theme.onSurface,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        ...tracksAsync.when(
          loading: () => <Widget>[
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, _) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: ShimmerBox(
                    width: MediaQuery.of(context).size.width - 32,
                    height: 40,
                  ),
                ),
                childCount: 6,
              ),
            ),
          ],
          error: (e, _) => <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: InlineError(
                  message: 'Could not load tracks',
                  onRetry: onRetryTracks,
                ),
              ),
            ),
          ],
          data: (tracks) {
            // Some Deezer endpoints return album tracks without nested album.
            final enriched = tracks
                .map((t) => t.album == null ? t.copyWith(album: album) : t)
                .toList(growable: false);
            return <Widget>[
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => DetailTrackRow(
                    track: enriched[i],
                    queue: enriched,
                    indexInQueue: i,
                    position: i + 1,
                    showArtist: false,
                  ),
                  childCount: enriched.length,
                ),
              ),
              if (album.artist != null)
                SliverToBoxAdapter(
                  child: _MoreFromArtist(artistId: album.artist!.id),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ];
          },
        ),
      ],
    );
  }

  String _meta(DeezerAlbum a) {
    final year = (a.releaseDate ?? '').length >= 4
        ? a.releaseDate!.substring(0, 4)
        : '';
    final tracks = a.nbTracks ?? 0;
    final mins = (a.duration ?? 0) ~/ 60;
    return <String>[
      if (year.isNotEmpty) year,
      if (tracks > 0) '$tracks tracks',
      if (mins > 0) '${mins}m',
    ].join('  ·  ');
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.theme});
  final AppTheme theme;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
      child: Row(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                PhosphorIconsRegular.caretLeft,
                color: theme.onSurface,
                size: 22,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'ALBUM',
            style: TextStyle(
              color: theme.onSurfaceMuted,
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 46),
        ],
      ),
    );
  }
}

class _MoreFromArtist extends ConsumerWidget {
  const _MoreFromArtist({required this.artistId});
  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(artistAlbumsProvider(artistId));
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'More from this artist'),
          SizedBox(
            height: 200,
            child: albumsAsync.when(
              loading: () => SnapHorizontalList(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (_, _) => const ShimmerSquare(size: 140),
                itemCount: 4,
                itemExtent: 140,
                spacing: 12,
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (albums) => SnapHorizontalList(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, i) =>
                    SizedBox(width: 140, child: AlbumCard(album: albums[i])),
                itemCount: albums.length,
                itemExtent: 140,
                spacing: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Center(child: ShimmerSquare(size: 200)),
          const SizedBox(height: 16),
          ShimmerBox(width: MediaQuery.of(context).size.width - 48, height: 24),
          const SizedBox(height: 8),
          ShimmerBox(
            width: (MediaQuery.of(context).size.width - 48) * 0.6,
            height: 14,
          ),
        ],
      ),
    );
  }
}
