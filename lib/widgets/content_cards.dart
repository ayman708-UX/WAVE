import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../core/api/models/deezer_album.dart';
import '../core/api/models/deezer_artist.dart';
import '../core/api/models/deezer_playlist.dart';
import '../core/api/models/deezer_track.dart';
import '../core/audio/player_providers.dart';
import '../core/downloads/download_providers.dart';
import '../core/downloads/download_status.dart';
import '../core/router/app_router.dart';
import '../core/storage/recently_played.dart';
import '../core/theme/app_theme.dart';
import 'on_device_badge.dart';

/// Album-cover sized card with title + subtitle, used by Made-for-you,
/// New releases, Mixes, Editorial, etc.
class CoverCard extends ConsumerWidget {
  const CoverCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.size = 150,
    this.shape = BoxShape.rectangle,
    this.overlay,
  });

  final String? imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final double size;
  final BoxShape shape;

  /// Optional gradient overlay rendered over the cover (used by mix cards).
  final Widget? overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final placeholder = Container(
      color: theme.surface,
      child: Center(
        child: Icon(
          PhosphorIconsRegular.musicNotes,
          color: theme.onSurfaceMuted,
          size: 32,
        ),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size == double.infinity ? null : size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  shape == BoxShape.circle ? 9999 : theme.cardRadius,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (imageUrl != null && imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        fadeInDuration: theme.fastDuration,
                        placeholder: (_, _) => placeholder,
                        errorWidget: (_, _, _) => placeholder,
                      )
                    else
                      placeholder,
                    if (overlay != null) Positioned.fill(child: overlay!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.onSurfaceMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Album card derived helper — pushes the album route on tap.
class AlbumCard extends ConsumerWidget {
  const AlbumCard({
    super.key,
    required this.album,
    this.size = 150,
    this.subtitleOverride,
  });

  final DeezerAlbum album;
  final double size;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CoverCard(
      imageUrl: album.coverBig ?? album.coverMedium ?? album.cover,
      title: album.title,
      subtitle: subtitleOverride ?? (album.artist?.name ?? 'Album'),
      size: size,
      onTap: () {
        ref.read(recentlyPlayedProvider.notifier).push(
              RecentEntry(
                kind: 'album',
                id: album.id,
                title: album.title,
                subtitle: album.artist?.name,
                imageUrl: album.coverMedium ?? album.cover,
                atMillis: DateTime.now().millisecondsSinceEpoch,
              ),
            );
        context.push(AppRoutes.albumPath(album.id));
      },
    );
  }
}

/// Playlist card.
class PlaylistCard extends ConsumerWidget {
  const PlaylistCard({super.key, required this.playlist, this.size = 150});

  final DeezerPlaylist playlist;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CoverCard(
      imageUrl:
          playlist.pictureBig ?? playlist.pictureMedium ?? playlist.picture,
      title: playlist.title,
      subtitle: playlist.creator?.name ?? 'Playlist',
      size: size,
      onTap: () {
        ref.read(recentlyPlayedProvider.notifier).push(
              RecentEntry(
                kind: 'playlist',
                id: playlist.id,
                title: playlist.title,
                subtitle: playlist.creator?.name,
                imageUrl: playlist.pictureMedium ?? playlist.picture,
                atMillis: DateTime.now().millisecondsSinceEpoch,
              ),
            );
        context.push(AppRoutes.playlistPath(playlist.id));
      },
    );
  }
}

/// Circular artist portrait.
class ArtistCircle extends ConsumerWidget {
  const ArtistCircle({super.key, required this.artist, this.size = 110});

  final DeezerArtist artist;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CoverCard(
      imageUrl: artist.pictureBig ?? artist.pictureMedium ?? artist.picture,
      title: artist.name,
      subtitle: 'Artist',
      size: size,
      shape: BoxShape.circle,
      onTap: () {
        ref.read(recentlyPlayedProvider.notifier).push(
              RecentEntry(
                kind: 'artist',
                id: artist.id,
                title: artist.name,
                imageUrl: artist.pictureMedium ?? artist.picture,
                atMillis: DateTime.now().millisecondsSinceEpoch,
              ),
            );
        context.push(AppRoutes.artistPath(artist.id));
      },
    );
  }
}

/// Compact track row used in the trending list. Tapping plays the track in
/// the context of the supplied [queue].
class TrackRow extends ConsumerWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.queue,
    required this.indexInQueue,
    this.showRank = false,
    this.onTapOverride,
  });

  final DeezerTrack track;
  final List<DeezerTrack> queue;
  final int indexInQueue;
  final bool showRank;
  final VoidCallback? onTapOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final cover = track.album?.coverMedium ??
        track.album?.cover ??
        track.album?.coverSmall;
    final onDevice = isTrackOnDevice(
      track,
      ref.watch(downloadedTracksProvider),
    );
    final placeholder = Container(
      width: 48,
      height: 48,
      color: theme.surface,
      child: Icon(
        PhosphorIconsRegular.musicNote,
        color: theme.onSurfaceMuted,
        size: 18,
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTapOverride ??
          () async {
            final controls = ref.read(playerControlsProvider);
            await controls.playTracks(queue, startIndex: indexInQueue);
            if (context.mounted) {
              await ref.read(recentlyPlayedProvider.notifier).push(
                    RecentEntry(
                      kind: 'track',
                      id: track.id,
                      title: track.title,
                      subtitle: track.artist?.name,
                      imageUrl: cover,
                      atMillis: DateTime.now().millisecondsSinceEpoch,
                    ),
                  );
            }
          },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: <Widget>[
            if (showRank)
              SizedBox(
                width: 28,
                child: Text(
                  '${indexInQueue + 1}',
                  style: TextStyle(
                    color: theme.onSurfaceMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 6),
              child: cover != null
                  ? CachedNetworkImage(
                      imageUrl: cover,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => placeholder,
                      errorWidget: (_, _, _) => placeholder,
                    )
                  : placeholder,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist?.name ?? 'Unknown artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                  if (onDevice)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: OnDeviceBadge(theme: theme),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmtDuration(track.duration),
              style: TextStyle(
                color: theme.onSurfaceMuted,
                fontSize: 12,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


String _fmtDuration(int? secs) {
  if (secs == null || secs <= 0) return '--:--';
  final m = secs ~/ 60;
  final s = secs % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Track card for displaying tracks in a slider.
class TrackCard extends ConsumerWidget {
  const TrackCard({
    super.key,
    required this.track,
    required this.queue,
    this.size = 150,
  });

  final DeezerTrack track;
  final List<DeezerTrack> queue;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final cover = track.album?.coverBig ?? track.album?.coverMedium ?? track.album?.cover;
    final onDevice = isTrackOnDevice(
      track,
      ref.watch(downloadedTracksProvider),
    );
    return CoverCard(
      imageUrl: cover,
      title: track.title,
      subtitle: onDevice
          ? '${track.artist?.name ?? 'Track'} · On device'
          : (track.artist?.name ?? 'Track'),
      size: size,
      overlay: onDevice
          ? Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: OnDeviceBadge(theme: theme, compact: true),
              ),
            )
          : null,
      onTap: () async {
        final controls = ref.read(playerControlsProvider);
        final indexInQueue = queue.indexOf(track);
        await controls.playTracks(queue, startIndex: indexInQueue >= 0 ? indexInQueue : 0);
        if (context.mounted) {
          await ref.read(recentlyPlayedProvider.notifier).push(
                RecentEntry(
                  kind: 'track',
                  id: track.id,
                  title: track.title,
                  subtitle: track.artist?.name,
                  imageUrl: cover,
                  atMillis: DateTime.now().millisecondsSinceEpoch,
                ),
              );
        }
      },
    );
  }
}
