import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../core/theme/app_theme.dart';

/// Custom replacement for `SearchBar` / AppBar search. Pure `TextField`
/// wrapped in a themed pill with leading magnifier and trailing clear.
class WaveSearchBar extends StatelessWidget {
  const WaveSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    this.hint = 'Search artists, songs, albums…',
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 999),
          border: Border.all(color: theme.onSurface.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        height: 48,
        child: Row(
          children: <Widget>[
            Icon(
              PhosphorIconsRegular.magnifyingGlass,
              color: theme.onSurfaceMuted,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                cursorColor: theme.accent,
                cursorWidth: 1.5,
                style: TextStyle(
                  color: theme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: TextStyle(
                    color: theme.onSurfaceMuted,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.text.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    controller.clear();
                    onChanged('');
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      PhosphorIconsRegular.x,
                      color: theme.onSurfaceMuted,
                      size: 18,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Recent search chip — custom (NOT Material `Chip`).
class RecentSearchChip extends StatelessWidget {
  const RecentSearchChip({
    super.key,
    required this.label,
    required this.onTap,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(theme.cardRadius == 0 ? 0 : 999),
          border: Border.all(color: theme.onSurface.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              PhosphorIconsRegular.clockCounterClockwise,
              size: 13,
              color: theme.onSurfaceMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  PhosphorIconsRegular.x,
                  size: 13,
                  color: theme.onSurfaceMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
