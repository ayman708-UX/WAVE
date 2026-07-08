import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class ContextMenuItem {
  const ContextMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

/// Custom context menu surfaced via [showWaveContextMenu]. Replaces
/// `PopupMenuButton`, `showMenu`, and `showModalBottomSheet` defaults.
class WaveContextMenu extends StatelessWidget {
  const WaveContextMenu({super.key, required this.items});

  final List<ContextMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 14),
        border: Border.all(color: theme.onSurface.withValues(alpha: 0.06)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < items.length; i++)
            _MenuTile(
              item: items[i],
              isFirst: i == 0,
              isLast: i == items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.item,
    required this.isFirst,
    required this.isLast,
  });

  final ContextMenuItem item;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final color = item.destructive ? theme.error : theme.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context, rootNavigator: true).pop();
        item.onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: isLast
                ? BorderSide.none
                : BorderSide(color: theme.onSurface.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(item.icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [items] as a contextual overlay anchored at [origin]. Animates up
/// from the press point with a spring scale + fade.
Future<void> showWaveContextMenu({
  required BuildContext context,
  required Offset origin,
  required List<ContextMenuItem> items,
}) async {
  final theme = AppThemeScope.of(context);
  final size = MediaQuery.of(context).size;
  final menuWidth = 260.0;
  final estimatedHeight = items.length * 48.0 + 16;
  final dx = (origin.dx - menuWidth / 2).clamp(8.0, size.width - menuWidth - 8);
  final dy = (origin.dy + 8).clamp(40.0, size.height - estimatedHeight - 40);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'context-menu',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: theme.normalDuration,
    pageBuilder: (_, _, _) {
      return Stack(
        children: <Widget>[
          Positioned(
            left: dx,
            top: dy,
            child: WaveContextMenu(items: items),
          ),
        ],
      );
    },
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return Opacity(
        opacity: anim.value,
        child: Transform.scale(
          scale: 0.85 + curved.value * 0.15,
          alignment: Alignment(
            (origin.dx / size.width) * 2 - 1,
            (origin.dy / size.height) * 2 - 1,
          ),
          child: child,
        ),
      );
    },
  );
}
