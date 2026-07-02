import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/api/models/deezer_track.dart';
import '../../core/api/models/queue_state.dart';
import '../../core/audio/player_providers.dart';
import '../../core/theme/app_theme.dart';
import '../context_menu.dart';

/// The drag-up queue sheet shown over the Now Playing screen.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final queue = ref.watch(queueSnapshotProvider);
    final controls = ref.read(playerControlsProvider);
    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: theme.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: <Widget>[
                Text(
                  queue.isRelatedMode ? 'RELATED' : 'QUEUE',
                  style: TextStyle(
                    color: theme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => controls.toggleRelatedMode(),
                  icon: Icon(
                    queue.isRelatedMode ? PhosphorIconsRegular.queue : PhosphorIconsRegular.radio,
                    size: 16,
                  ),
                  label: Text(
                    queue.isRelatedMode ? 'Back to Queue' : 'Play Related',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: queue.isRelatedMode ? theme.surface : theme.accent,
                    foregroundColor: queue.isRelatedMode ? theme.onSurface : theme.background,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                const SizedBox(width: 8),
                _SmallAction(
                  label: 'Clear',
                  icon: PhosphorIconsRegular.trash,
                  destructive: true,
                  onTap: () => controls.clearQueue(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _QueueList(queue: queue),
          ),
        ],
      ),
    );
  }
}

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.queue});

  final QueueState queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    final controls = ref.read(playerControlsProvider);
    final upcoming = queue.upcoming;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        if (queue.current != null)
          SliverToBoxAdapter(
            child: _Header(text: 'Now playing', color: theme.accent),
          ),
        if (queue.current != null)
          SliverToBoxAdapter(
            child: _QueueRow(
              track: queue.current!,
              highlighted: true,
              onTap: () {},
            ),
          ),
        if (upcoming.isNotEmpty)
          SliverToBoxAdapter(
            child: _Header(text: 'Up next', color: theme.onSurfaceMuted),
          ),
        SliverReorderableList(
          itemCount: upcoming.length,
          itemBuilder: (context, i) => Material(
            key: ValueKey<int>(upcoming[i].id ^ i),
            color: Colors.transparent,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (d) =>
                  _menu(context, ref, upcoming[i], d.globalPosition),
              child: _QueueRow(
                track: upcoming[i],
                highlighted: false,
                onTap: () => controls.skipToIndex(i),
                trailing: ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Icon(
                      PhosphorIconsRegular.dotsSixVertical,
                      color: theme.onSurfaceMuted,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
          onReorder: (a, b) => controls.reorderQueue(a, b > a ? b - 1 : b),
        ),
        if (queue.history.isNotEmpty)
          SliverToBoxAdapter(
            child: _Header(text: 'History', color: theme.onSurfaceMuted),
          ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final reversedIndex = queue.history.length - 1 - i;
              return _QueueRow(
                track: queue.history[reversedIndex],
                highlighted: false,
                onTap: () => controls.skipToHistory(reversedIndex),
                dim: true,
              );
            },
            childCount: queue.history.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  void _menu(BuildContext context, WidgetRef ref, DeezerTrack t, Offset origin) {
    showWaveContextMenu(
      context: context,
      origin: origin,
      items: <ContextMenuItem>[
        ContextMenuItem(
          icon: PhosphorIconsRegular.queue,
          label: 'Play next',
          onTap: () => ref.read(playerControlsProvider).addToQueueNext(t),
        ),
        ContextMenuItem(
          icon: PhosphorIconsRegular.x,
          label: 'Remove from queue',
          destructive: true,
          onTap: () {
            // The list rebuilds when service emits — index lookup at call time.
            final state = ref.read(queueSnapshotProvider);
            final idx = state.upcoming.indexWhere((e) => e.id == t.id);
            if (idx >= 0) {
              ref.read(playerControlsProvider).removeFromQueue(idx);
            }
          },
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.track,
    required this.highlighted,
    required this.onTap,
    this.trailing,
    this.dim = false,
  });

  final DeezerTrack track;
  final bool highlighted;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final cover = track.album?.coverSmall ?? track.album?.cover;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: dim ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: highlighted ? theme.accent.withValues(alpha: 0.08) : null,
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: cover != null
                      ? CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              ColoredBox(color: theme.background),
                          errorWidget: (_, _, _) =>
                              ColoredBox(color: theme.background),
                        )
                      : ColoredBox(color: theme.background),
                ),
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
                        color: highlighted ? theme.accent : theme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final color = destructive ? theme.error : theme.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
