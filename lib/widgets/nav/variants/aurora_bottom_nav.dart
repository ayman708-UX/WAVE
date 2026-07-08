import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../nav_destination.dart';

/// Aurora theme: floating tab bar with no background — just icons. Active
/// indicator is a soft organic blob behind the icon that bounces with a
/// spring on tap.
class AuroraBottomNav extends StatelessWidget {
  const AuroraBottomNav({
    super.key,
    required this.theme,
    required this.destinations,
    required this.activeIndex,
    required this.onSelected,
  });

  final AppTheme theme;
  final List<NavDestination> destinations;
  final int activeIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: theme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(32),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: theme.accent.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < destinations.length; i++)
              Expanded(
                child: _AuroraTab(
                  theme: theme,
                  destination: destinations[i],
                  active: i == activeIndex,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AuroraTab extends StatefulWidget {
  const _AuroraTab({
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
  State<_AuroraTab> createState() => _AuroraTabState();
}

class _AuroraTabState extends State<_AuroraTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    upperBound: 1,
  );

  @override
  void didUpdateWidget(covariant _AuroraTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _bounce,
        builder: (context, _) {
          final scale = widget.active
              ? 1 +
                    0.18 *
                        Curves.elasticOut.transform(_bounce.value) *
                        (1 - _bounce.value * 0.6)
              : 1.0;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              if (widget.active)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: widget.theme.accent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                ),
              Transform.scale(
                scale: scale,
                child: Icon(
                  widget.active
                      ? widget.destination.iconFilled
                      : widget.destination.icon,
                  size: 24,
                  color: widget.active
                      ? widget.theme.accent
                      : widget.theme.onSurfaceMuted,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
