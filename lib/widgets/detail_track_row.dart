import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../core/api/models/deezer_track.dart';
import '../core/audio/player_providers.dart';
import '../core/downloads/download_manager.dart';
import '../core/downloads/download_providers.dart';
import '../core/downloads/download_status.dart';
import '../core/storage/library_providers.dart';
import '../core/theme/app_theme.dart';
import 'on_device_badge.dart';
import 'context_menu.dart';

/// Tracklist row used by Album / Playlist pages. Shows numbered position,
/// track title + artist (when [showArtist]), explicit badge, duration, and
/// fires the supplied [queue] starting at [indexInQueue] on tap.
class DetailTrackRow extends ConsumerWidget {
  const DetailTrackRow({
    super.key,
    required this.track,
    required this.queue,
    required this.indexInQueue,
    required this.position,
    this.showArtist = true,
    this.dragHandle = false,
  });

  final DeezerTrack track;
  final List<DeezerTrack> queue;
  final int indexInQueue;
  final int position;
  final bool showArtist;
  final bool dragHandle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final liked = ref
        .watch(likedTracksProvider)
        .any((t) => t.id == track.id);
    final downloaded = isTrackOnDevice(
      track,
      ref.watch(downloadedTracksProvider),
    );
    final downloading = ref.watch(activeDownloadsProvider).containsKey(track.id);
    final cover = track.album?.coverSmall ?? track.album?.cover;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          ref.read(playerControlsProvider).playTracks(queue, startIndex: indexInQueue),
      onLongPressStart: (d) => _menu(
        context,
        ref,
        d.globalPosition,
        liked,
        downloaded,
        downloading,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 28,
              child: Text(
                '$position',
                style: TextStyle(
                  color: theme.onSurfaceMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            if (showArtist) ...<Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 4),
                child: SizedBox(
                  width: 40,
                  height: 40,
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
              const SizedBox(width: 12),
            ],
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (showArtist && (track.artist?.name ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        track.artist!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.onSurfaceMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (downloaded)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: OnDeviceBadge(theme: theme),
                    ),
                ],
              ),
            ),
            if (track.explicitLyrics == true) ...<Widget>[
              const SizedBox(width: 8),
              _ExplicitBadge(theme: theme),
            ],
            const SizedBox(width: 12),
            Text(
              _fmtDuration(track.duration),
              style: TextStyle(
                color: theme.onSurfaceMuted,
                fontSize: 12,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
            if (dragHandle) ...<Widget>[
              const SizedBox(width: 12),
              ReorderableDragStartListener(
                index: indexInQueue,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Icon(
                    PhosphorIconsRegular.dotsSixVertical,
                    color: theme.onSurfaceMuted,
                    size: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _menu(
    BuildContext context,
    WidgetRef ref,
    Offset origin,
    bool liked,
    bool downloaded,
    bool downloading,
  ) {
    showWaveContextMenu(
      context: context,
      origin: origin,
      items: <ContextMenuItem>[
        ContextMenuItem(
          icon: liked
              ? PhosphorIconsFill.heart
              : PhosphorIconsRegular.heart,
          label: liked ? 'Remove from liked' : 'Add to liked',
          onTap: () =>
              ref.read(likedTracksProvider.notifier).toggle(track),
        ),
        ContextMenuItem(
          icon: PhosphorIconsRegular.queue,
          label: 'Play next',
          onTap: () =>
              ref.read(playerControlsProvider).addToQueueNext(track),
        ),
        ContextMenuItem(
          icon: PhosphorIconsRegular.playlist,
          label: 'Add to queue',
          onTap: () =>
              ref.read(playerControlsProvider).addToQueueLast(track),
        ),
        ContextMenuItem(
          icon: downloaded
              ? PhosphorIconsFill.cloudCheck
              : PhosphorIconsRegular.cloudArrowDown,
          label: downloading
              ? 'Downloading...'
              : (downloaded ? 'Delete download' : 'Download track'),
          onTap: downloading
              ? () {}
              : () {
                  final manager = ref.read(downloadManagerProvider);
                  if (downloaded) {
                    manager.deleteDownload(track.id);
                  } else {
                    manager.downloadTrack(track);
                  }
                },
        ),
      ],
    );
  }
}

class _ExplicitBadge extends StatelessWidget {
  const _ExplicitBadge({required this.theme});
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.onSurfaceMuted.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        'E',
        style: TextStyle(
          color: theme.onSurfaceMuted,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          height: 1,
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
