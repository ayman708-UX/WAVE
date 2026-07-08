import 'package:flutter/material.dart';

/// Identifier for each of the six built-in themes.
enum AppThemeId { obsidian, vapor, brutalist, aurora, neonGrid, minimalMono }

/// Animation personality for a theme.
enum AnimationPersonality { snappy, floaty, punchy, smooth, instant, crossfade }

/// Card / tile style.
enum CardStyle { sharp, glass, brutal, organic, neonOutline, hairline }

/// A WAVE theme is far more than a colour palette. It bundles colours,
/// typography, animation curves and structural personality so that each
/// theme can completely re-skin the app.
@immutable
class AppTheme {
  const AppTheme({
    required this.id,
    required this.name,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.accent,
    required this.error,
    required this.displayFont,
    required this.bodyFont,
    required this.cardStyle,
    required this.cardRadius,
    required this.animation,
    required this.fastDuration,
    required this.normalDuration,
    required this.slowDuration,
    required this.defaultCurve,
  });

  final AppThemeId id;
  final String name;
  final Brightness brightness;

  // Colours.
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color accent;
  final Color error;

  // Typography (Google Fonts family names).
  final String displayFont;
  final String bodyFont;

  // Structure.
  final CardStyle cardStyle;
  final double cardRadius;

  // Motion.
  final AnimationPersonality animation;
  final Duration fastDuration;
  final Duration normalDuration;
  final Duration slowDuration;
  final Curve defaultCurve;

  /// Builds a Material `ThemeData` for the few places where the framework
  /// requires one (e.g. `MaterialApp.theme`). The actual app UI reads colours
  /// directly from this `AppTheme` via `AppThemeScope`.
  ThemeData toMaterialTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: background,
        secondary: accent,
        onSecondary: background,
        error: error,
        onError: background,
        surface: surface,
        onSurface: onSurface,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }
}

/// Inherited widget that exposes the active [AppTheme] to the entire widget
/// tree. Use `AppThemeScope.of(context)` instead of `Theme.of(context)`.
class AppThemeScope extends InheritedWidget {
  const AppThemeScope({super.key, required this.theme, required super.child});

  final AppTheme theme;

  static AppTheme of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope not found in widget tree');
    return scope!.theme;
  }

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) => oldWidget.theme != theme;
}
