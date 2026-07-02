import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/themes.dart';
import '../../widgets/snap_horizontal_list.dart';
import '../../widgets/theme_morph.dart';

/// Horizontal carousel of 6 theme cards. Tapping a card kicks off the
/// theme-switch morph animation from the tap location.
class ThemeSwitcherScreen extends ConsumerWidget {
  const ThemeSwitcherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Themes',
            style: TextStyle(
              color: theme.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Each theme rebuilds the player, navigation and motion language.',
            style: TextStyle(color: theme.onSurfaceMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 320,
            child: SnapHorizontalList(
              padding: EdgeInsets.zero,
              itemCount: AppThemes.all.length,
              itemExtent: 220,
              spacing: 16,
              itemBuilder: (context, i) {
                final t = AppThemes.all[i];
                return _ThemeCard(active: t.id == theme.id, theme: t);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends ConsumerWidget {
  const _ThemeCard({required this.active, required this.theme});

  final bool active;
  final AppTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (cardCtx) {
        return GestureDetector(
          onTapDown: (details) {
            ref.read(themeMorphControllerProvider.notifier).switchTo(
                  target: theme.id,
                  origin: details.globalPosition,
                );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 220,
            decoration: BoxDecoration(
              color: theme.background,
              borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 4 : 16),
              border: Border.all(
                color: active ? theme.accent : theme.onSurface.withValues(alpha: 0.15),
                width: active ? 2 : 1,
              ),
              boxShadow: active
                  ? <BoxShadow>[
                      BoxShadow(
                        color: theme.accent.withValues(alpha: 0.4),
                        blurRadius: 26,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: _ThemeMockup(theme: theme, active: active),
          ),
        );
      },
    );
  }
}

class _ThemeMockup extends StatelessWidget {
  const _ThemeMockup({required this.theme, required this.active});

  final AppTheme theme;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Mock header.
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                theme.name.toUpperCase(),
                style: TextStyle(
                  color: theme.onSurface,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              if (active)
                Icon(
                  PhosphorIconsFill.checkCircle,
                  size: 14,
                  color: theme.accent,
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Mock album art.
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 8),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      theme.accent.withValues(alpha: 0.6),
                      theme.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Mock track title.
          Container(
            width: double.infinity,
            height: 8,
            color: theme.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 6),
          Container(
            width: 80,
            height: 6,
            color: theme.onSurfaceMuted.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          // Mock controls.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _miniDot(theme.onSurfaceMuted),
              _miniDot(theme.accent, big: true),
              _miniDot(theme.onSurfaceMuted),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniDot(Color c, {bool big = false}) {
    return Container(
      width: big ? 22 : 14,
      height: big ? 22 : 14,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }
}
