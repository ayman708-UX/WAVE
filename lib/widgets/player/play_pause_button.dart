import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_theme.dart';

/// Animated play / pause button. The icon morphs through scale + cross-fade
/// and a ripple radiates from the centre on tap.
class PlayPauseButton extends StatefulWidget {
  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onTap,
    this.size = 64,
    this.iconColor,
    this.background,
    this.shape = BoxShape.circle,
  });

  final bool isPlaying;
  final VoidCallback onTap;
  final double size;
  final Color? iconColor;
  final Color? background;
  final BoxShape shape;

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  void _handle() {
    _ripple.forward(from: 0);
    widget.onTap();
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    final fg = widget.iconColor ?? theme.background;
    final bg = widget.background ?? theme.accent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handle,
      child: SizedBox(
        width: widget.size + 24,
        height: widget.size + 24,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              AnimatedBuilder(
                animation: _ripple,
                builder: (context, _) {
                  final t = _ripple.value;
                  if (t == 0) return const SizedBox.shrink();
                  return Container(
                    width: widget.size + (t * 28),
                    height: widget.size + (t * 28),
                    decoration: BoxDecoration(
                      shape: widget.shape,
                      color: bg.withValues(alpha: (1 - t) * 0.35),
                    ),
                  );
                },
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: bg,
                  shape: widget.shape,
                  borderRadius: widget.shape == BoxShape.rectangle
                      ? BorderRadius.circular(12)
                      : null,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: anim, child: child),
                  ),
                  child: Icon(
                    widget.isPlaying
                        ? PhosphorIconsFill.pause
                        : PhosphorIconsFill.play,
                    key: ValueKey<bool>(widget.isPlaying),
                    color: fg,
                    size: widget.size * 0.42,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
