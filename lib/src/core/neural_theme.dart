import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The visual language of every neural widget.
enum NeuralDesign {
  /// Pure and modern (the default since 1.1.0): liquid glass surfaces,
  /// prismatic strokes, soft depth and restrained glow.
  liquid,

  /// The original sci-fi look: neon strokes, strong bloom, HUD ticks.
  neon,
}

/// Iridescent stroke colors used by the liquid design.
abstract final class NeuralSpectrum {
  /// For dark backgrounds.
  static const List<Color> dark = [
    Color(0xFFFF8A5B), // coral
    Color(0xFFFF4FB8), // magenta
    Color(0xFF8D6BFF), // violet
    Color(0xFF39B8FF), // azure
  ];

  /// For light backgrounds (deeper, so strokes keep contrast).
  static const List<Color> light = [
    Color(0xFFF2642F),
    Color(0xFFDC3597),
    Color(0xFF6A46EE),
    Color(0xFF1A8AE6),
  ];
}

/// App-wide overrides for every Rehoboam neural widget.
///
/// Register it once in your [ThemeData.extensions] to restyle the whole
/// package; anything left `null` falls back to the ambient [ColorScheme]:
///
/// ```dart
/// ThemeData(
///   colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan),
///   extensions: const [
///     NeuralThemeData(design: NeuralDesign.neon, glowIntensity: 1.4),
///   ],
/// )
/// ```
///
/// A color passed directly to a widget always wins over this extension.
@immutable
class NeuralThemeData extends ThemeExtension<NeuralThemeData> {
  /// Creates a neural theme. Every field is optional.
  const NeuralThemeData({
    this.design,
    this.accent,
    this.secondary,
    this.track,
    this.foreground,
    this.success,
    this.warning,
    this.error,
    this.glowIntensity,
    this.spectrum,
  });

  /// Liquid (default) or neon.
  final NeuralDesign? design;

  /// Primary color. Defaults to [ColorScheme.primary].
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

  /// Multiplier for every glow and bloom, `0` disables glow. Defaults to
  /// `0.45` in the liquid design and `1` in the neon design.
  final double? glowIntensity;

  /// Iridescent stroke colors for the liquid design (2-6 colors).
  /// Defaults to [NeuralSpectrum].
  final List<Color>? spectrum;

  @override
  NeuralThemeData copyWith({
    NeuralDesign? design,
    Color? accent,
    Color? secondary,
    Color? track,
    Color? foreground,
    Color? success,
    Color? warning,
    Color? error,
    double? glowIntensity,
    List<Color>? spectrum,
  }) {
    return NeuralThemeData(
      design: design ?? this.design,
      accent: accent ?? this.accent,
      secondary: secondary ?? this.secondary,
      track: track ?? this.track,
      foreground: foreground ?? this.foreground,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      glowIntensity: glowIntensity ?? this.glowIntensity,
      spectrum: spectrum ?? this.spectrum,
    );
  }

  @override
  NeuralThemeData lerp(covariant NeuralThemeData? other, double t) {
    if (other == null) return this;
    final a = spectrum;
    final b = other.spectrum;
    return NeuralThemeData(
      design: t < 0.5 ? design : other.design,
      accent: Color.lerp(accent, other.accent, t),
      secondary: Color.lerp(secondary, other.secondary, t),
      track: Color.lerp(track, other.track, t),
      foreground: Color.lerp(foreground, other.foreground, t),
      success: Color.lerp(success, other.success, t),
      warning: Color.lerp(warning, other.warning, t),
      error: Color.lerp(error, other.error, t),
      glowIntensity: lerpDouble(glowIntensity, other.glowIntensity, t),
      spectrum: a != null && b != null && a.length == b.length
          ? [for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!]
          : (t < 0.5 ? a : b),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NeuralThemeData &&
      other.design == design &&
      other.accent == accent &&
      other.secondary == secondary &&
      other.track == track &&
      other.foreground == foreground &&
      other.success == success &&
      other.warning == warning &&
      other.error == error &&
      other.glowIntensity == glowIntensity &&
      _listEq(other.spectrum, spectrum);

  @override
  int get hashCode => Object.hash(
        design,
        accent,
        secondary,
        track,
        foreground,
        success,
        warning,
        error,
        glowIntensity,
        spectrum == null ? null : Object.hashAll(spectrum!),
      );
}

bool _listEq(List<Color>? a, List<Color>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
    this.design = NeuralDesign.liquid,
    this.spectrum = NeuralSpectrum.dark,
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
    final design = ext?.design ?? NeuralDesign.liquid;
    final liquid = design == NeuralDesign.liquid;
    final glow = ext?.glowIntensity ?? (liquid ? 0.45 : 1.0);
    final spec = ext?.spectrum;
    return NeuralPalette(
      design: design,
      accent: accent ?? ext?.accent ?? scheme.primary,
      secondary: secondary ?? ext?.secondary ?? scheme.tertiary,
      track: track ??
          ext?.track ??
          scheme.onSurface.withValues(
            alpha: liquid ? (dark ? 0.09 : 0.06) : (dark ? 0.12 : 0.08),
          ),
      foreground: ext?.foreground ?? scheme.onSurface,
      surface: scheme.surface,
      success: ext?.success ??
          (dark ? const Color(0xFF4ADE9B) : const Color(0xFF12A26B)),
      warning: ext?.warning ??
          (dark ? const Color(0xFFFFC857) : const Color(0xFFC98A00)),
      error: ext?.error ?? scheme.error,
      glowIntensity: glow.isFinite ? glow.clamp(0.0, 3.0) : 1.0,
      brightness: scheme.brightness,
      spectrum: spec != null && spec.length >= 2
          ? spec
          : (dark ? NeuralSpectrum.dark : NeuralSpectrum.light),
    );
  }

  /// Liquid or neon.
  final NeuralDesign design;

  /// Primary color.
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

  /// Iridescent stroke colors (liquid design).
  final List<Color> spectrum;

  /// Whether the ambient theme is dark.
  bool get isDark => brightness == Brightness.dark;

  /// Whether the liquid design is active.
  bool get isLiquid => design == NeuralDesign.liquid;

  /// Colors for a gradient stroke: the spectrum in the liquid design, the
  /// secondary-to-accent pair in the neon design.
  List<Color> get strokeColors => isLiquid ? spectrum : [secondary, accent];

  /// Color at position [t] (`0..1`) along [strokeColors].
  Color strokeAt(double t) {
    final c = strokeColors;
    final x = (t.isFinite ? t.clamp(0.0, 1.0) : 0.0) * (c.length - 1);
    final i = x.floor().clamp(0, c.length - 2);
    return Color.lerp(c[i], c[i + 1], x - i)!;
  }

  @override
  bool operator ==(Object other) =>
      other is NeuralPalette &&
      other.design == design &&
      other.accent == accent &&
      other.secondary == secondary &&
      other.track == track &&
      other.foreground == foreground &&
      other.surface == surface &&
      other.success == success &&
      other.warning == warning &&
      other.error == error &&
      other.glowIntensity == glowIntensity &&
      other.brightness == brightness &&
      _listEq(other.spectrum, spectrum);

  @override
  int get hashCode => Object.hash(
      design,
      accent,
      secondary,
      track,
      foreground,
      surface,
      success,
      warning,
      error,
      glowIntensity,
      brightness,
      Object.hashAll(spectrum));
}
