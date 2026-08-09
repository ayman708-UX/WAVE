import 'dart:io' show Platform;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/models/deezer_track.dart';
import '../../core/api/models/player_state.dart' hide RepeatMode;
import '../../core/api/models/player_state.dart' as ps show RepeatMode;
import '../../core/api/models/queue_state.dart';
import '../../core/audio/player_providers.dart';
import '../../core/audio/sleep_timer.dart';
import '../../core/router/app_router.dart';
import '../../core/storage/library_providers.dart';
import '../../core/api/deezer_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../audiobooks/services/audiobook_providers.dart';
import '../../core/models/audiobook.dart';
import 'dart:convert';
import '../../widgets/player/heart_like_button.dart';
import '../../widgets/player/lyrics_view.dart';
import '../../widgets/player/more_options_sheet.dart';
import '../../widgets/player/play_pause_button.dart';
import '../../widgets/player/progress_bar.dart';
import '../../widgets/player/queue_panel.dart';
import '../../widgets/player/sleep_timer_dial.dart';
import '../../widgets/player/waveform_bars.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/download_providers.dart';
import '../../core/downloads/download_status.dart';

/// Now-Playing screen. Branches on `theme.id` to render six distinct
/// presentations of the same player state.
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  bool _showLyrics = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final player = ref.watch(playerSnapshotProvider);
    final queue = ref.watch(queueSnapshotProvider);
    final track = player.currentTrack;
    if (track == null) {
      return _EmptyShell(theme: theme);
    }
    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: player.transitionDuration,
                reverseDuration: player.transitionDuration,
                child: KeyedSubtree(
                  key: ValueKey('bg_${theme.id}'),
                  child: _buildBackground(theme, track, player),
                ),
              ),
            ),
            Column(
              children: <Widget>[
                _buildTopBar(context, theme, queue),
                Expanded(
                  child: _showLyrics
                      ? LyricsView(track: track)
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          reverseDuration: const Duration(milliseconds: 300),
                          child: KeyedSubtree(
                            key: const ValueKey('art_section'),
                            child: _buildArtSection(theme, track, player),
                          ),
                        ),
                ),
                _buildControlsSection(context, theme, track, player, queue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(
    AppTheme theme,
    DeezerTrack track,
    PlayerState player,
  ) {
    final cover = track.album?.coverXl ?? track.album?.coverBig;
    switch (theme.id) {
      case AppThemeId.vapor:
      case AppThemeId.aurora:
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            AnimatedSwitcher(
              duration: player.transitionDuration,
              switchInCurve: Curves.linear,
              switchOutCurve: Curves.linear,
              child: cover != null
                  ? CachedNetworkImage(
                      key: ValueKey(cover),
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => ColoredBox(
                        key: ValueKey('ph_$cover'),
                        color: theme.background,
                      ),
                      errorWidget: (_, _, _) => ColoredBox(
                        key: ValueKey('err_$cover'),
                        color: theme.background,
                      ),
                    )
                  : ColoredBox(
                      key: const ValueKey('empty_bg'),
                      color: theme.background,
                    ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: ColoredBox(
                color: theme.background.withValues(alpha: 0.65),
              ),
            ),
          ],
        );
      case AppThemeId.neonGrid:
        return const _NeonGridBackground();
      case AppThemeId.obsidian:
      case AppThemeId.brutalist:
      case AppThemeId.minimalMono:
        return const SizedBox.expand();
    }
  }

  Widget _buildTopBar(BuildContext context, AppTheme theme, QueueState queue) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: <Widget>[
          _IconButton(
            icon: PhosphorIconsRegular.caretLeft,
            onTap: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          Column(
            children: <Widget>[
              Text(
                'PLAYING FROM',
                style: TextStyle(
                  color: theme.onSurfaceMuted,
                  fontSize: 9,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                queue.isRelatedMode ? 'Related' : 'Queue',
                style: TextStyle(
                  color: theme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const Spacer(),
          _IconButton(
            icon: PhosphorIconsRegular.dotsThreeVertical,
            onTap: () {
              final t = ref.read(playerSnapshotProvider).currentTrack;
              if (t != null) {
                showWaveSheet<void>(
                  context: context,
                  builder: (_) =>
                      MoreOptionsSheet(track: t, isFromNowPlaying: true),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildArtSection(AppTheme theme, DeezerTrack track, PlayerState s) {
    final cover = track.album?.coverBig ?? track.album?.cover;
    final radius = switch (theme.id) {
      AppThemeId.brutalist => 0.0,
      AppThemeId.minimalMono => 4.0,
      AppThemeId.aurora => 28.0,
      AppThemeId.vapor => 24.0,
      AppThemeId.obsidian => 8.0,
      AppThemeId.neonGrid => 6.0,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (theme.id == AppThemeId.neonGrid)
                _NeonGlow(color: theme.accent),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: theme.id == AppThemeId.brutalist
                      ? Border.all(color: theme.onSurface, width: 3)
                      : null,
                  boxShadow: <BoxShadow>[
                    if (theme.id != AppThemeId.brutalist &&
                        theme.id != AppThemeId.minimalMono)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 30,
                        offset: const Offset(0, 18),
                      ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: AnimatedSwitcher(
                  duration: s.transitionDuration,
                  switchInCurve: Curves.linear,
                  switchOutCurve: Curves.linear,
                  child: cover != null
                      ? CachedNetworkImage(
                          key: ValueKey(cover),
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => ColoredBox(
                            key: ValueKey('ph_$cover'),
                            color: theme.surface,
                          ),
                          errorWidget: (_, _, _) => Container(
                            key: ValueKey('err_$cover'),
                            color: theme.surface,
                            child: Icon(
                              PhosphorIconsRegular.musicNote,
                              color: theme.onSurfaceMuted,
                              size: 56,
                            ),
                          ),
                        )
                      : ColoredBox(
                          key: const ValueKey('empty_cover'),
                          color: theme.surface,
                        ),
                ),
              ),
              if (theme.id == AppThemeId.neonGrid)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: WaveformBars(
                      isPlaying: s.status == PlaybackStatus.playing,
                      height: 36,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsSection(
    BuildContext context,
    AppTheme theme,
    DeezerTrack track,
    PlayerState player,
    QueueState queue,
  ) {
    final liked = ref.watch(likedTracksProvider).any((t) => t.id == track.id);
    final timer = ref.watch(sleepTimerProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AnimatedSwitcher(
                  duration: player.transitionDuration,
                  reverseDuration: player.transitionDuration,
                  layoutBuilder:
                      (Widget? currentChild, List<Widget> previousChildren) {
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: <Widget>[
                            ...previousChildren,
                            // ignore: use_null_aware_elements
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                  child: Column(
                    key: ValueKey('text_${track.id}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () async {
                          var id = track.artist?.id;
                          if (id == null || id == 0) {
                            try {
                              final fullTrack = await ref
                                  .read(deezerApiClientProvider)
                                  .getTrack(track.id);
                              id = fullTrack.artist?.id;
                            } catch (_) {}
                          }
                          if (id != null && id != 0) {
                            if (context.mounted) {
                              context.pop();
                              context.push(AppRoutes.artistPath(id));
                            }
                          }
                        },
                        child: Text(
                          track.artist?.name ?? '',
                          style: TextStyle(
                            color: theme.onSurfaceMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _DownloadButton(track: track),
              Consumer(
                builder: (context, ref, child) {
                  final isAudiobook = track.link == 'wave://audiobook';
                  bool isItemLiked = liked;
                  
                  if (isAudiobook && track.preview != null) {
                    try {
                      final payload = jsonDecode(track.preview!);
                      final book = Audiobook.fromJson(payload['audiobook']);
                      isItemLiked = ref.watch(likedAudiobooksProvider.notifier).isLiked(book.uuid);
                    } catch (_) {}
                  }

                  return HeartLikeButton(
                    liked: isItemLiked,
                    onTap: () {
                      if (isAudiobook && track.preview != null) {
                        try {
                          final payload = jsonDecode(track.preview!);
                          final book = Audiobook.fromJson(payload['audiobook']);
                          ref.read(likedAudiobooksProvider.notifier).toggle(book);
                        } catch (_) {}
                      } else {
                        ref.read(likedTracksProvider.notifier).toggle(track);
                      }
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          WaveProgressBar(
            position: player.position,
            duration: player.duration > Duration.zero
                ? player.duration
                : Duration(seconds: track.duration ?? 0),
            buffered: player.buffered,
            onSeek: (p) => ref.read(playerControlsProvider).seek(p),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  _fmt(player.position),
                  style: TextStyle(
                    color: theme.onSurfaceMuted,
                    fontSize: 11,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Text(
                  _fmt(
                    player.duration > Duration.zero
                        ? player.duration
                        : Duration(seconds: track.duration ?? 0),
                  ),
                  style: TextStyle(
                    color: theme.onSurfaceMuted,
                    fontSize: 11,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _ToggleIconButton(
                icon: PhosphorIconsRegular.shuffle,
                active: player.shuffle,
                onTap: () => ref
                    .read(playerControlsProvider)
                    .setShuffle(!player.shuffle),
              ),
              _IconButton(
                icon: PhosphorIconsFill.skipBack,
                size: 28,
                onTap: () => ref.read(playerControlsProvider).skipPrevious(),
              ),
              PlayPauseButton(
                isPlaying: player.status == PlaybackStatus.playing,
                onTap: () => ref.read(playerControlsProvider).togglePlayPause(),
                size: switch (theme.id) {
                  AppThemeId.brutalist => 60,
                  AppThemeId.minimalMono => 56,
                  _ => 64,
                },
                shape: theme.id == AppThemeId.brutalist
                    ? BoxShape.rectangle
                    : BoxShape.circle,
              ),
              _IconButton(
                icon: PhosphorIconsFill.skipForward,
                size: 28,
                onTap: () => ref.read(playerControlsProvider).skipNext(),
              ),
              _ToggleIconButton(
                icon: player.repeat == ps.RepeatMode.one
                    ? PhosphorIconsRegular.repeatOnce
                    : PhosphorIconsRegular.repeat,
                active: player.repeat != ps.RepeatMode.off,
                onTap: () => ref
                    .read(playerControlsProvider)
                    .setRepeat(
                      ps.RepeatMode.values[(player.repeat.index + 1) %
                          ps.RepeatMode.values.length],
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 0,
            children: <Widget>[
              _BottomTextButton(
                icon: queue.isRelatedMode
                    ? PhosphorIconsRegular.radio
                    : PhosphorIconsRegular.queue,
                label: queue.isRelatedMode ? 'RELATED' : 'QUEUE',
                onTap: () => showWaveSheet<void>(
                  context: context,
                  builder: (_) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.78,
                    child: QueuePanel(
                      onClose: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
              _BottomTextButton(
                icon: PhosphorIconsRegular.musicNotes,
                label: _showLyrics ? 'COVER' : 'LYRICS',
                onTap: () => setState(() => _showLyrics = !_showLyrics),
              ),
              _BottomTextButton(
                icon: PhosphorIconsRegular.clockCounterClockwise,
                label: timer != null && timer.isActive
                    ? _fmt(timer.remaining)
                    : 'TIMER',
                accent: timer != null && timer.isActive,
                onTap: () => showWaveSheet<void>(
                  context: context,
                  builder: (_) => const SleepTimerDial(),
                ),
              ),
            ],
          ),
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _DesktopVolumeSlider(player: player),
            ),
        ],
      ),
    );
  }
}

class _DesktopVolumeSlider extends ConsumerWidget {
  const _DesktopVolumeSlider({required this.player});
  final PlayerState player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final isMuted = player.volume == 0;
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            ref.read(playerControlsProvider).setVolume(isMuted ? 1.0 : 0.0);
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            child: Icon(
              isMuted
                  ? PhosphorIconsFill.speakerX
                  : player.volume < 0.5
                  ? PhosphorIconsFill.speakerLow
                  : PhosphorIconsFill.speakerHigh,
              color: theme.onSurfaceMuted,
              size: 20,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: theme.accent,
              inactiveTrackColor: theme.onSurface.withValues(alpha: 0.1),
              thumbColor: theme.accent,
              overlayColor: theme.accent.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: player.volume,
              onChanged: (v) => ref.read(playerControlsProvider).setVolume(v),
            ),
          ),
        ),
      ],
    );
  }
}

String _fmt(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap, this.size = 22});
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(icon, color: theme.onSurface, size: size),
      ),
    );
  }
}

class _ToggleIconButton extends StatelessWidget {
  const _ToggleIconButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          icon,
          color: active ? theme.accent : theme.onSurfaceMuted,
          size: 22,
        ),
      ),
    );
  }
}

class _BottomTextButton extends StatelessWidget {
  const _BottomTextButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final color = accent ? theme.accent : theme.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyShell extends StatelessWidget {
  const _EmptyShell({required this.theme});
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: <Widget>[
                  _IconButton(
                    icon: PhosphorIconsRegular.caretLeft,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      PhosphorIconsRegular.musicNotes,
                      color: theme.onSurfaceMuted,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nothing is playing',
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeonGlow extends StatelessWidget {
  const _NeonGlow({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 60,
            spreadRadius: 8,
          ),
        ],
      ),
    );
  }
}

class _NeonGridBackground extends StatelessWidget {
  const _NeonGridBackground();

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return CustomPaint(
      painter: _GridPainter(
        bg: theme.background,
        line: theme.accent.withValues(alpha: 0.06),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.bg, required this.line});
  final Color bg;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.bg != bg || old.line != line;
}

class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.track});
  final DeezerTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final downloadedTracks = ref.watch(downloadedTracksProvider);
    final isDownloaded = isTrackOnDevice(track, downloadedTracks);

    final activeDownloads = ref.watch(activeDownloadsProvider);
    final progress = activeDownloads[track.id];
    final isDownloading = progress != null;

    if (isDownloading) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            strokeWidth: 2,
            color: theme.accent,
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final manager = ref.read(downloadManagerProvider);
        if (isDownloaded) {
          manager.deleteDownload(track.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed from device: ${track.title}')),
          );
        } else {
          manager.downloadTrack(track);
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          isDownloaded
              ? PhosphorIconsFill.cloudCheck
              : PhosphorIconsRegular.cloudArrowDown,
          color: isDownloaded ? theme.accent : theme.onSurfaceMuted,
          size: 24,
        ),
      ),
    );
  }
}
