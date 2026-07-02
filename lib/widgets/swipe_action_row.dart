import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../core/theme/app_theme.dart';

/// Custom horizontal swipe-to-action row. Replaces `Dismissible` since the
/// spec mandates custom animations and revealed action panels.
///
/// Swiping left reveals [trailingAction]; swiping right reveals
/// [leadingAction]. Either may be omitted. When the swipe passes the
/// threshold and the user lifts, the corresponding `onAction` fires and the
/// row springs back. The row never disappears on its own — removal is up to
/// the caller.
class SwipeActionRow extends StatefulWidget {
  const SwipeActionRow({
    super.key,
    required this.child,
    this.leadingIcon,
    this.leadingColor,
    this.leadingLabel,
    this.onLeading,
    this.trailingIcon,
    this.trailingColor,
    this.trailingLabel,
    this.onTrailing,
    this.actionWidth = 88,
  });

  final Widget child;

  final IconData? leadingIcon;
  final Color? leadingColor;
  final String? leadingLabel;
  final VoidCallback? onLeading;

  final IconData? trailingIcon;
  final Color? trailingColor;
  final String? trailingLabel;
  final VoidCallback? onTrailing;

  final double actionWidth;

  @override
  State<SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<SwipeActionRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 0,
    );
  }

  /// Dx offset normalised: positive => row dragged right (leading visible).
  double _dx = 0;

  void _onUpdate(DragUpdateDetails d) {
    setState(() {
      _dx = (_dx + d.delta.dx).clamp(
        widget.onTrailing != null ? -widget.actionWidth * 1.6 : 0.0,
        widget.onLeading != null ? widget.actionWidth * 1.6 : 0.0,
      );
    });
  }

  void _onEnd(DragEndDetails d) {
    final triggered = _dx.abs() > widget.actionWidth * 0.7;
    if (triggered) {
      if (_dx > 0) {
        widget.onLeading?.call();
      } else {
        widget.onTrailing?.call();
      }
    }
    setState(() => _dx = 0);
    _ctrl.value = 0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);
    return ClipRect(
      child: Stack(
        children: <Widget>[
          // Leading reveal (swipe right).
          if (widget.onLeading != null && _dx > 0)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: _dx.abs().clamp(0, widget.actionWidth),
                  color: widget.leadingColor ?? theme.accent,
                  child: Icon(
                    widget.leadingIcon ?? PhosphorIconsRegular.plus,
                    color: theme.background,
                    size: 22,
                  ),
                ),
              ),
            ),
          // Trailing reveal (swipe left).
          if (widget.onTrailing != null && _dx < 0)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: _dx.abs().clamp(0, widget.actionWidth),
                  color: widget.trailingColor ?? theme.error,
                  child: Icon(
                    widget.trailingIcon ?? PhosphorIconsRegular.heartBreak,
                    color: theme.background,
                    size: 22,
                  ),
                ),
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(_dx, 0, 0),
              color: theme.background,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
