import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../core/theme/app_theme.dart';

/// Compact inline error widget used inside a section that failed to load.
/// Spec rule: never a full-page error unless catastrophic.
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: theme.error.withValues(alpha: 0.08),
        border: Border.all(color: theme.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 10),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            PhosphorIconsRegular.warningCircle,
            color: theme.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.onSurface, fontSize: 12),
            ),
          ),
          if (onRetry != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRetry,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  'RETRY',
                  style: TextStyle(
                    color: theme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
