import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Pill-style sub-tab strip used by Library + Discover. Replaces TabBar.
class WaveSubTabs extends StatelessWidget {
  const WaveSubTabs({
    super.key,
    required this.labels,
    required this.active,
    required this.onTap,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 12),
    this.scrollable = true,
  });

  final List<String> labels;
  final int active;
  final ValueChanged<int> onTap;
  final EdgeInsets padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final children = <Widget>[
      for (var i = 0; i < labels.length; i++)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: theme.fastDuration,
              curve: theme.defaultCurve,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active == i ? theme.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(
                  theme.cardRadius == 0 ? 0 : 999,
                ),
                border: Border.all(
                  color: active == i
                      ? theme.accent
                      : theme.onSurface.withValues(alpha: 0.16),
                ),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  color: active == i ? theme.background : theme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
    ];
    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(children: children),
      );
    }
    return Padding(
      padding: padding,
      child: Row(children: children),
    );
  }
}
