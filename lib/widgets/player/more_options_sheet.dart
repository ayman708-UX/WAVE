import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/models/deezer_track.dart';
import '../../core/audio/player_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import 'add_to_playlist_sheet.dart';
import 'sleep_timer_dial.dart';

/// Generic slide-up sheet using `showGeneralDialog`. Drag handle, themed.
Future<T?> showWaveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'sheet',
    barrierColor: (barrierColor ?? Colors.black).withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.bottomCenter,
      child: Material(color: Colors.transparent, child: builder(ctx)),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// "More options" sheet shown from Now Playing.
class MoreOptionsSheet extends ConsumerWidget {
  const MoreOptionsSheet({
    super.key,
    required this.track,
    this.isFromNowPlaying = false,
  });
  final DeezerTrack track;
  final bool isFromNowPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final controls = ref.read(playerControlsProvider);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
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
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist?.name ?? '',
                          style: TextStyle(
                            color: theme.onSurfaceMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Row(
              icon: PhosphorIconsRegular.queue,
              label: 'Play next',
              onTap: () {
                controls.addToQueueNext(track);
                Navigator.of(context).pop();
              },
            ),
            _Row(
              icon: PhosphorIconsRegular.playlist,
              label: 'Add to queue',
              onTap: () {
                controls.addToQueueLast(track);
                Navigator.of(context).pop();
              },
            ),
            _Row(
              icon: PhosphorIconsRegular.plus,
              label: 'Add to playlist',
              onTap: () {
                Navigator.of(context).pop();
                showAddToPlaylistSheet(context, track);
              },
            ),
             _Row(
              icon: PhosphorIconsRegular.vinylRecord,
              label: 'Go to album',
              onTap: () {
                final id = track.album?.id;
                if (id != null) {
                  Navigator.of(context).pop();
                  final router = GoRouter.of(context);
                  if (isFromNowPlaying) {
                    Navigator.of(context).pop();
                  }
                  router.push(AppRoutes.albumPath(id));
                }
              },
            ),
            _Row(
              icon: PhosphorIconsRegular.user,
              label: 'Go to artist',
              onTap: () {
                final id = track.artist?.id;
                if (id != null) {
                  Navigator.of(context).pop();
                  final router = GoRouter.of(context);
                  if (isFromNowPlaying) {
                    Navigator.of(context).pop();
                  }
                  router.push(AppRoutes.artistPath(id));
                }
              },
            ),

            _Row(
              icon: PhosphorIconsRegular.clockCounterClockwise,
              label: 'Sleep timer',
              onTap: () {
                Navigator.of(context).pop();
                showWaveSheet<void>(
                  context: context,
                  builder: (_) => const SleepTimerDial(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: <Widget>[
            Icon(icon, color: theme.onSurface, size: 20),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
