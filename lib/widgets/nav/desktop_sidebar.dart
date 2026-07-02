import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/audio/player_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import 'nav_destination.dart';

/// Permanent left sidebar shown on desktop layouts. 240px wide.
class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({
    super.key,
    required this.theme,
    required this.activeIndex,
    required this.onSelected,
  });

  final AppTheme theme;
  final int activeIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTrack = ref.watch(hasActiveTrackProvider);
    final track = ref.watch(playerSnapshotProvider).currentTrack;
    return Container(
      width: 240,
      color: theme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Text(
              'WAVE',
              style: TextStyle(
                color: theme.accent,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
          ),
          for (int i = 0; i < kNavDestinations.length; i++)
            _SidebarItem(
              theme: theme,
              destination: kNavDestinations[i],
              active: i == activeIndex,
              onTap: () => onSelected(i),
            ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push(AppRoutes.settings),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: <Widget>[
                  Icon(
                    PhosphorIconsRegular.gear,
                    size: 18,
                    color: theme.onSurfaceMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Settings',
                    style: TextStyle(
                      color: theme.onSurfaceMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasTrack && track != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.onSurface.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.theme,
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final AppTheme theme;
  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: theme.fastDuration,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? theme.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: active
              ? Border(left: BorderSide(color: theme.accent, width: 3))
              : null,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              active ? destination.iconFilled : destination.icon,
              size: 18,
              color: active ? theme.accent : theme.onSurfaceMuted,
            ),
            const SizedBox(width: 12),
            Text(
              destination.label,
              style: TextStyle(
                color: active ? theme.onSurface : theme.onSurfaceMuted,
                fontSize: 14,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
