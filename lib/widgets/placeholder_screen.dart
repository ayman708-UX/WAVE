import 'package:flutter/widgets.dart';

import '../core/theme/app_theme.dart';

/// Generic placeholder used by every Phase 1 stub screen so the app shell
/// can be navigated end-to-end before real screens land.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.label,
    required this.theme,
  });

  final String label;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: theme.onSurface,
          fontSize: 28,
          letterSpacing: 4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
