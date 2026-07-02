import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../core/theme/app_theme.dart';

class OnDeviceBadge extends StatelessWidget {
  const OnDeviceBadge({
    super.key,
    required this.theme,
    this.compact = false,
  });

  final AppTheme theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 7,
        vertical: compact ? 2.5 : 3,
      ),
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            PhosphorIconsFill.cloudCheck,
            color: theme.accent,
            size: compact ? 10 : 11,
          ),
          const SizedBox(width: 4),
          Text(
            'On device',
            style: TextStyle(
              color: theme.accent,
              fontSize: compact ? 9.5 : 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
