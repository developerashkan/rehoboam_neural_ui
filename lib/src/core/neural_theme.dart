import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// App-wide overrides for every Rehoboam neural widget.
///
/// Register it once in your [ThemeData.extensions] to recolor the whole
/// package; anything left `null` falls back to the ambient [ColorScheme]:
///
/// ```dart
/// ThemeData(
///   colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan),
///   extensions: const [
///     NeuralThemeData(accent: Color(0xFF00E5FF), glowIntensity: 1.4),
///   ],
/// )
/// ```
///
/// A color passed directly to a widget always wins over this extension.
@immutable
class NeuralThemeData extends ThemeExtension<NeuralThemeData> {
  /// Creates a neural theme. Every field is optional.
  const NeuralThemeData({
    this.accent,
    this.secondary,
    this.track,
    this.foreground,
    this.success,
    this.warning,
    this.error,
    this.glowIntensity,
  });

  /// Primary glow color. Defaults to [ColorScheme.primary].
  final Color? accent;

  /// Second gradient stop. Defaults to [ColorScheme.tertiary].
  final Color? secondary;

  /// Unfilled tracks and inactive cells. Defaults to a faint
  /// [ColorScheme.onSurface].
  final Color? track;

  /// Text and fine detail. Defaults to [ColorScheme.onSurface].
  final Color? foreground;

  /// Positive state (verified scan, online presence).
  final Color? success;

  /// Cautionary state (away presence, gauge thresholds).
  final Color? warning;

  /// Negative state. Defaults to [ColorScheme.error].
  final Color? error;

  /// Multiplier for every glow and bloom, `0` disables glow. Defaults to `1`.
  final double? glowIntensity;

  @override
  NeuralThemeData copyWith({
    Color? accent,
    Color? secondary,
    Color? track,
    Color? foreground,
    Color? success,
    Color? warning,
    Color? error,
    double? glowIntensity,
  }) {
    return NeuralThemeData(
      accent: accent ?? this.accent,
      secondary: secondary ?? this.secondary,
      track: track ?? this.track,
      foreground: foreground ?? this.foreground,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      glowIntensity: glowIntensity ?? this.glowIntensity,
    );
  }

  @override
  NeuralThemeData lerp(covariant NeuralThemeData? other, double t) {
    if (other == null) return this;
    return NeuralThemeData(
      accent: Color.lerp(accent, other.accent, t),
      secondary: Color.lerp(secondary, other.secondary, t),
      track: Color.lerp(track, other.track, t),
      foreground: Color.lerp(foreground, other.foreground, t),
      success: Color.lerp(success, other.success, t),
      warning: Color.lerp(warning, other.warning, t),
      error: Color.lerp(error, other.error, t),
      glowIntensity: lerpDouble(glowIntensity, other.glowIntensity, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NeuralThemeData &&
      other.accent == accent &&
      other.secondary == secondary &&
      other.track == track &&
      other.foreground == foreground &&
      other.success == success &&
      other.warning == warning &&
      other.error == error &&
      other.glowIntensity == glowIntensity;

  @override
  int get hashCode => Object.hash(
        accent,
        secondary,
        track,
        foreground,
        success,
        warning,
        error,
        glowIntensity,
      );
}

/// The resolved colors a neural widget paints with.
///
/// Resolution order: explicit widget argument, then [NeuralThemeData], then
/// the ambient [ColorScheme] (so light and dark themes both work).
@immutable
class NeuralPalette {
  /// Creates a palette from explicit colors.
  const NeuralPalette({
    required this.accent,
    required this.secondary,
    required this.track,
    required this.foreground,
    required this.surface,
    required this.success,
    required this.warning,
    required this.error,
    required this.glowIntensity,
    required this.brightness,
  });

  /// Resolves the palette for [context]. [accent], [secondary] and [track]
  /// are per-widget overrides.
  factory NeuralPalette.of(
    BuildContext context, {
    Color? accent,
    Color? secondary,
    Color? track,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ext = theme.extension<NeuralThemeData>();
    final dark = scheme.brightness == Brightness.dark;
    final glow = ext?.glowIntensity ?? 1.0;
    return NeuralPalette(
      accent: accent ?? ext?.accent ?? scheme.primary,
      secondary: secondary ?? ext?.secondary ?? scheme.tertiary,
      track: track ??
          ext?.track ??
          scheme.onSurface.withValues(alpha: dark ? 0.12 : 0.08),
      foreground: ext?.foreground ?? scheme.onSurface,
      surface: scheme.surface,
      success: ext?.success ??
          (dark ? const Color(0xFF4ADE9B) : const Color(0xFF12A26B)),
      warning: ext?.warning ??
          (dark ? const Color(0xFFFFC857) : const Color(0xFFC98A00)),
      error: ext?.error ?? scheme.error,
      glowIntensity: glow.isFinite ? glow.clamp(0.0, 3.0) : 1.0,
      brightness: scheme.brightness,
    );
  }

  /// Primary glow color.
  final Color accent;

  /// Secondary gradient color.
  final Color secondary;

  /// Unfilled track color.
  final Color track;

  /// Text / fine detail color.
  final Color foreground;

  /// Background surface the widget sits on.
  final Color surface;

  /// Positive state color.
  final Color success;

  /// Cautionary state color.
  final Color warning;

  /// Negative state color.
  final Color error;

  /// Glow multiplier in `[0, 3]`.
  final double glowIntensity;

  /// Theme brightness.
  final Brightness brightness;

  /// Whether the ambient theme is dark.
  bool get isDark => brightness == Brightness.dark;

  @override
  bool operator ==(Object other) =>
      other is NeuralPalette &&
      other.accent == accent &&
      other.secondary == secondary &&
      other.track == track &&
      other.foreground == foreground &&
      other.surface == surface &&
      other.success == success &&
      other.warning == warning &&
      other.error == error &&
      other.glowIntensity == glowIntensity &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(accent, secondary, track, foreground, surface,
      success, warning, error, glowIntensity, brightness);
}
