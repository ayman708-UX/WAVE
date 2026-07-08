import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 32-bar animated waveform — used by the Neon-Grid Now Playing variant.
class WaveformBars extends StatefulWidget {
  const WaveformBars({
    super.key,
    required this.isPlaying,
    this.barCount = 32,
    this.height = 80,
    this.color,
  });

  final bool isPlaying;
  final int barCount;
  final double height;
  final Color? color;

  @override
  State<WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<WaveformBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant WaveformBars old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.isPlaying) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _WavePainter(
              t: _ctrl.value,
              barCount: widget.barCount,
              color: widget.color ?? theme.accent,
              isPlaying: widget.isPlaying,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.t,
    required this.barCount,
    required this.color,
    required this.isPlaying,
  });

  final double t;
  final int barCount;
  final Color color;
  final bool isPlaying;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final gap = 3.0;
    final barWidth = (size.width - gap * (barCount - 1)) / barCount;
    for (var i = 0; i < barCount; i++) {
      final phase = (i / barCount) * math.pi * 4 + t * math.pi * 2;
      final amp = isPlaying
          ? 0.45 + 0.55 * (math.sin(phase) * 0.5 + 0.5)
          : 0.18;
      final h = size.height * amp;
      final x = i * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - h) / 2, barWidth, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.t != t || old.isPlaying != isPlaying || old.color != color;
}

/// Tiny 3-bar equalizer icon shown in the mini-player when playing.
class MiniEqualizerIcon extends StatefulWidget {
  const MiniEqualizerIcon({
    super.key,
    required this.isPlaying,
    this.color,
    this.size = 14,
  });
  final bool isPlaying;
  final Color? color;
  final double size;

  @override
  State<MiniEqualizerIcon> createState() => _MiniEqualizerIconState();
}

class _MiniEqualizerIconState extends State<MiniEqualizerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant MiniEqualizerIcon old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isPlaying && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _EqPainter(
          t: _ctrl.value,
          color: widget.color ?? theme.accent,
        ),
      ),
    );
  }
}

class _EqPainter extends CustomPainter {
  _EqPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final barW = size.width / 5;
    final heights = <double>[
      0.4 + 0.6 * (math.sin(t * math.pi * 2) * 0.5 + 0.5),
      0.4 + 0.6 * (math.sin(t * math.pi * 2 + 1) * 0.5 + 0.5),
      0.4 + 0.6 * (math.sin(t * math.pi * 2 + 2) * 0.5 + 0.5),
    ];
    for (var i = 0; i < 3; i++) {
      final h = size.height * heights[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * 2 * barW, size.height - h, barW, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqPainter old) => old.t != t;
}
