import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_notifier.dart';
import '../core/theme/themes.dart';

/// Snapshot of the in-progress full-screen morph transition between themes.
@immutable
class ThemeMorphState {
  const ThemeMorphState({
    required this.origin,
    required this.color,
    required this.tag,
  });

  final Offset origin;
  final Color color;

  /// Monotonically-increasing tag so each request triggers a fresh animation
  /// even if origin & colour happen to match.
  final int tag;
}

/// Drives the theme morph: starts the overlay animation, swaps the active
/// theme at the midpoint, then clears the overlay.
class ThemeMorphController extends Notifier<ThemeMorphState?> {
  int _seq = 0;

  @override
  ThemeMorphState? build() => null;

  Future<void> switchTo({
    required AppThemeId target,
    required Offset origin,
  }) async {
    final current = ref.read(themeProvider);
    if (current.id == target) return;
    final next = AppThemes.byId(target);
    state = ThemeMorphState(origin: origin, color: next.accent, tag: ++_seq);
    await Future<void>.delayed(const Duration(milliseconds: 280));
    await ref.read(themeProvider.notifier).setTheme(target);
    await Future<void>.delayed(const Duration(milliseconds: 360));
    if (state?.tag == _seq) state = null;
  }
}

final themeMorphControllerProvider =
    NotifierProvider<ThemeMorphController, ThemeMorphState?>(
      ThemeMorphController.new,
    );

/// Full-screen overlay that draws the expanding (then contracting) circle.
class ThemeMorphOverlay extends ConsumerStatefulWidget {
  const ThemeMorphOverlay({super.key});

  @override
  ConsumerState<ThemeMorphOverlay> createState() => _ThemeMorphOverlayState();
}

class _ThemeMorphOverlayState extends ConsumerState<ThemeMorphOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );

  int? _activeTag;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final morph = ref.watch(themeMorphControllerProvider);
    if (morph != null && morph.tag != _activeTag) {
      _activeTag = morph.tag;
      _ctrl.forward(from: 0);
    } else if (morph == null) {
      _activeTag = null;
    }
    if (morph == null && !_ctrl.isAnimating) {
      return const IgnorePointer(child: SizedBox.shrink());
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final size = MediaQuery.of(context).size;
          final maxR =
              math.sqrt(size.width * size.width + size.height * size.height) +
              80;
          final t = _ctrl.value;
          final phase = t < 0.5 ? t * 2 : (1 - t) * 2;
          final r = Curves.easeOutCubic.transform(phase) * maxR;
          final color = morph?.color ?? Colors.transparent;
          return CustomPaint(
            size: size,
            painter: _CirclePainter(
              center: morph?.origin ?? Offset(size.width / 2, size.height / 2),
              radius: r,
              color: color,
            ),
          );
        },
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  _CirclePainter({
    required this.center,
    required this.radius,
    required this.color,
  });

  final Offset center;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    final paint = Paint()..color = color;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _CirclePainter old) =>
      old.center != center || old.radius != radius || old.color != color;
}
