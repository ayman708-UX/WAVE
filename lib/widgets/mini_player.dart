import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../core/api/models/player_state.dart';
import '../core/audio/player_providers.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

/// Persistent mini-player. Animates in from the bottom when a track is
/// loaded. Tap expands to the Now Playing screen.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerSnapshotProvider);
    final track = state.currentTrack;
    final visible = track != null;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1),
      duration: theme.normalDuration,
      curve: theme.defaultCurve,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: theme.fastDuration,
        child: visible
            ? _MiniPlayerCard(theme: theme, state: state)
            : const SizedBox(height: 0),
      ),
    );
  }
}

class _MiniPlayerCard extends ConsumerWidget {
  const _MiniPlayerCard({required this.theme, required this.state});

  final AppTheme theme;
  final PlayerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = state.currentTrack!;
    final cover = track.album?.coverSmall ?? track.album?.cover;
    final isPlaying = state.status == PlaybackStatus.playing;
    final progress = state.duration.inMilliseconds == 0
        ? 0.0
        : (state.position.inMilliseconds / state.duration.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(AppRoutes.nowPlaying),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 14),
          border: Border.all(color: theme.onSurface.withValues(alpha: 0.08)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Hairline progress on top.
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: SizedBox(
                height: 2.5,
                child: LinearProgressIndicatorRaw(
                  value: progress,
                  color: theme.accent,
                  background: theme.onSurface.withValues(alpha: 0.08),
                ),
              ),
            ),
            SizedBox(
              height: 60,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: cover != null
                          ? CachedNetworkImage(
                              imageUrl: cover,
                              fit: BoxFit.cover,
                              placeholder: (c, _) =>
                                  Container(color: theme.background),
                              errorWidget: (c, _, _) => Container(
                                color: theme.accent.withValues(alpha: 0.2),
                              ),
                            )
                          : Container(
                              color: theme.accent.withValues(alpha: 0.2),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          track.title,
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
                          track.artist?.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.onSurfaceMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _MiniIconButton(
                    icon: isPlaying
                        ? PhosphorIconsRegular.pause
                        : PhosphorIconsRegular.play,
                    color: theme.onSurface,
                    onTap: () =>
                        ref.read(playerControlsProvider).togglePlayPause(),
                  ),
                  _MiniIconButton(
                    icon: PhosphorIconsRegular.skipForward,
                    color: theme.onSurface,
                    onTap: () => ref.read(playerControlsProvider).skipNext(),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

/// 1-px linear progress that doesn't use Material's [LinearProgressIndicator]
/// (which is forbidden by spec).
class LinearProgressIndicatorRaw extends StatelessWidget {
  const LinearProgressIndicatorRaw({
    super.key,
    required this.value,
    required this.color,
    required this.background,
  });

  final double value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return Stack(
          children: <Widget>[
            Container(width: c.maxWidth, color: background),
            Container(width: c.maxWidth * value, color: color),
          ],
        );
      },
    );
  }
}
