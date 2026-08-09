import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/device_profile.dart';

/// Material [InkWell] on touch/desktop; [FocusableControl] on Android TV for D-pad.
///
/// Pass either [borderRadius] ([BorderRadius.circular] etc.) or [cornerRadius].
class TvInkWell extends StatelessWidget {
  const TvInkWell({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.borderRadius,
    this.cornerRadius,
    this.customBorder,
    this.focusGlowColor,
    this.splashColor,
    this.hoverColor,
    this.highlightColor,
    this.focusColor,
    this.onHover,
    this.onFocusChange,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final BorderRadiusGeometry? borderRadius;
  final double? cornerRadius;
  final ShapeBorder? customBorder;
  final Color? focusGlowColor;
  final Color? splashColor;
  final Color? hoverColor;
  final Color? highlightColor;
  final Color? focusColor;
  final void Function(bool)? onHover;
  final void Function(bool)? onFocusChange;

  BorderRadiusGeometry _resolvedShape() {
    return borderRadius ?? BorderRadius.circular(cornerRadius ?? 12);
  }

  double _tvFocusCornerRadius() {
    if (customBorder is CircleBorder) return 999;
    final shape = _resolvedShape();
    if (shape is BorderRadius) {
      return shape.topLeft.x;
    }
    return cornerRadius ?? 12;
  }

  @override
  Widget build(BuildContext context) {
    final shape = _resolvedShape();
    final borderRadiusForInk =
        customBorder == null && shape is BorderRadius ? shape : null;

    if (!DeviceProfile.isAndroidTv) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onHover: onHover,
          onFocusChange: onFocusChange,
          customBorder: customBorder,
          borderRadius: borderRadiusForInk,
          splashColor: splashColor,
          hoverColor: hoverColor,
          highlightColor: highlightColor,
          focusColor: focusColor,
          child: child,
        ),
      );
    }

    Widget tv = FocusableControl(
      onTap: onTap,
      borderRadius: _tvFocusCornerRadius(),
      glowColor: focusGlowColor,
      child: child,
    );
    if (onLongPress != null) {
      tv = GestureDetector(onLongPress: onLongPress, child: tv);
    }
    return tv;
  }
}

/// Plain [GestureDetector] elsewhere; focus ring + Select on Android TV.
class TvGestureTap extends StatelessWidget {
  const TvGestureTap({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius = 12,
    this.behavior,
    this.onLongPress,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final double borderRadius;
  final HitTestBehavior? behavior;

  @override
  Widget build(BuildContext context) {
    if (!DeviceProfile.isAndroidTv) {
      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: behavior ?? HitTestBehavior.deferToChild,
        child: child,
      );
    }
    Widget tv = FocusableControl(
      onTap: onTap,
      borderRadius: borderRadius,
      child: child,
    );
    if (onLongPress != null) {
      tv = GestureDetector(onLongPress: onLongPress, child: tv);
    }
    return tv;
  }
}
