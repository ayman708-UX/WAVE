import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../core/theme/app_theme.dart';

/// "Play" + "Shuffle" button pair shown at the top of detail pages.
class PlayShufflePair extends StatelessWidget {
  const PlayShufflePair({
    super.key,
    required this.onPlay,
    required this.onShuffle,
  });

  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPlay,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.accent,
                borderRadius: BorderRadius.circular(
                  theme.cardRadius == 0 ? 0 : 999,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    PhosphorIconsFill.play,
                    color: theme.background,
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'PLAY',
                    style: TextStyle(
                      color: theme.background,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onShuffle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(
                theme.cardRadius == 0 ? 0 : 999,
              ),
              border: Border.all(color: theme.onSurface.withValues(alpha: 0.2)),
            ),
            child: Icon(
              PhosphorIconsRegular.shuffle,
              color: theme.onSurface,
              size: 16,
            ),
          ),
        ),
      ],
    );
  }
}
