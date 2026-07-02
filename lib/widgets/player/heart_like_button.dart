import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_theme.dart';

/// Heart toggle that triggers a 12-particle explosion on like.
class HeartLikeButton extends StatefulWidget {
  const HeartLikeButton({
    super.key,
    required this.liked,
    required this.onTap,
    this.size = 28,
  });

  final bool liked;
  final VoidCallback onTap;
  final double size;

  @override
  State<HeartLikeButton> createState() => _HeartLikeButtonState();
}

class _HeartLikeButtonState extends State<HeartLikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  void _handle() {
    if (!widget.liked) {
      _burst.forward(from: 0);
    }
    widget.onTap();
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final color = widget.liked ? theme.accent : theme.onSurface;
    final pad = widget.size + 40;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handle,
      child: SizedBox(
        width: pad,
        height: pad,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              AnimatedBuilder(
                animation: _burst,
                builder: (context, _) {
                  if (_burst.value == 0) return const SizedBox.shrink();
                  return SizedBox(
                    width: pad,
                    height: pad,
                    child: CustomPaint(
                      painter: _HeartParticlesPainter(
                        progress: _burst.value,
                        color: theme.accent,
                      ),
                    ),
                  );
                },
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(
                  widget.liked
                      ? PhosphorIconsFill.heart
                      : PhosphorIconsRegular.heart,
                  key: ValueKey<bool>(widget.liked),
                  color: color,
                  size: widget.size,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeartParticlesPainter extends CustomPainter {
  _HeartParticlesPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()..color = color.withValues(alpha: 1 - progress);
    const count = 12;
    final maxR = math.min(size.width, size.height) / 2;
    final dist = maxR * progress;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2;
      final dx = cx + math.cos(angle) * dist;
      final dy = cy + math.sin(angle) * dist;
      _drawHeart(canvas, Offset(dx, dy), 4 * (1 - progress * 0.6), paint);
    }
  }

  void _drawHeart(Canvas canvas, Offset c, double r, Paint p) {
    if (r <= 0) return;
    final path = Path();
    final w = r * 2;
    final h = r * 2;
    final x = c.dx - r;
    final y = c.dy - r;
    path.moveTo(x + w / 2, y + h * 0.85);
    path.cubicTo(
      x - w * 0.1, y + h * 0.55,
      x + w * 0.05, y + h * 0.05,
      x + w / 2, y + h * 0.3,
    );
    path.cubicTo(
      x + w * 0.95, y + h * 0.05,
      x + w * 1.1, y + h * 0.55,
      x + w / 2, y + h * 0.85,
    );
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _HeartParticlesPainter old) =>
      old.progress != progress;
}
