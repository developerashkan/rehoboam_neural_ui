import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';

/// Colors the gauge arc from [value] upward (e.g. warning above 70).
@immutable
class NeuralGaugeThreshold {
  /// Creates a threshold.
  const NeuralGaugeThreshold(this.value, this.color);

  /// Where this color starts, in the gauge's `min..max` units.
  final double value;

  /// Arc color at and above [value].
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is NeuralGaugeThreshold &&
      other.value == value &&
      other.color == color;

  @override
  int get hashCode => Object.hash(value, color);
}

/// An animated KPI ring / gauge with glow, ticks and a live readout.
///
/// Value changes sweep smoothly from the old to the new reading. The
/// readout is real text (scales with the system font size, readable by
/// screen readers); the arc mirrors in right-to-left locales.
///
/// ```dart
/// NeuralGauge(value: cpu, max: 100, unit: '%', label: 'CPU',
///   thresholds: const [NeuralGaugeThreshold(80, Colors.orange)])
/// ```
class NeuralGauge extends StatefulWidget {
  /// Creates a gauge.
  const NeuralGauge({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 100,
    this.size = 200,
    this.label,
    this.unit,
    this.valueFormatter,
    this.thresholds = const [],
    this.sweepDegrees = 270,
    this.strokeWidth,
    this.color,
    this.secondaryColor,
    this.trackColor,
    this.ticks = 40,
    this.duration = const Duration(milliseconds: 900),
    this.curve = Curves.easeOutCubic,
    this.semanticsLabel,
  });

  /// Current reading (clamped into `min..max`; NaN shows [min]).
  final double value;

  /// Lower bound.
  final double min;

  /// Upper bound.
  final double max;

  /// Diameter.
  final double size;

  /// Caption under the value, e.g. "CPU".
  final String? label;

  /// Unit after the value, e.g. "%".
  final String? unit;

  /// Formats the readout. Defaults to an integer, or one decimal below 10.
  final String Function(double value)? valueFormatter;

  /// Color bands. Sorted internally.
  final List<NeuralGaugeThreshold> thresholds;

  /// Arc length in degrees (`1..360`).
  final double sweepDegrees;

  /// Arc thickness. Defaults to `size / 13`.
  final double? strokeWidth;

  /// Arc end color. Defaults to the theme accent.
  final Color? color;

  /// Arc start color. Defaults to the theme secondary.
  final Color? secondaryColor;

  /// Track color.
  final Color? trackColor;

  /// Tick marks around the arc (`0` hides them).
  final int ticks;

  /// Sweep animation length.
  final Duration duration;

  /// Sweep animation curve.
  final Curve curve;

  /// Accessibility label. Defaults to [label] or "Gauge".
  final String? semanticsLabel;

  @override
  State<NeuralGauge> createState() => _NeuralGaugeState();
}

class _NeuralGaugeState extends State<NeuralGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.duration);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _ctrl, curve: widget.curve);
  late final ValueNotifier<double> _shown = ValueNotifier(_target());
  late double _from = _shown.value;
  late double _to = _shown.value;

  double get _lo => finiteOr(math.min(widget.min, widget.max), 0);
  double get _hi => finiteOr(math.max(widget.min, widget.max), 1);

  double _target() {
    final v = widget.value;
    if (v.isNaN) return _lo;
    return v.clamp(_lo, _hi);
  }

  @override
  void initState() {
    super.initState();
    _curve.addListener(() {
      _shown.value = _from + (_to - _from) * _curve.value;
    });
  }

  @override
  void didUpdateWidget(NeuralGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ctrl.duration = widget.duration;
    _curve.curve = widget.curve;
    final target = _target();
    if (target != _to) {
      if (reduceMotionOf(context) || widget.duration == Duration.zero) {
        _ctrl.stop();
        _from = _to = target;
        _shown.value = target;
      } else {
        _from = _shown.value;
        _to = target;
        _ctrl.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _ctrl.dispose();
    _shown.dispose();
    super.dispose();
  }

  String _format(double v) {
    final f = widget.valueFormatter;
    if (f != null) return f(v);
    return v.abs() < 10 && v != v.roundToDouble()
        ? v.toStringAsFixed(1)
        : v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = NeuralPalette.of(
      context,
      accent: widget.color,
      secondary: widget.secondaryColor,
      track: widget.trackColor,
    );
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final size = finiteOr(widget.size, 200).clamp(0.0, double.maxFinite);
    final sorted = [...widget.thresholds]
      ..sort((a, b) => a.value.compareTo(b.value));
    final text = theme.textTheme;

    return Semantics(
      label: widget.semanticsLabel ?? widget.label ?? 'Gauge',
      value: '${_format(_target())}${widget.unit ?? ''}',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: NeuralGaugePainter(
                value: _shown,
                min: _lo,
                max: _hi,
                palette: palette,
                thresholds: sorted,
                sweep: finiteOr(widget.sweepDegrees, 270).clamp(1.0, 360.0) *
                    math.pi /
                    180,
                strokeWidth: widget.strokeWidth,
                ticks: math.max(0, widget.ticks),
                rtl: rtl,
              ),
              child: Padding(
                padding: EdgeInsets.all(size * 0.24),
                child: FittedBox(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _shown,
                    builder: (context, v, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: _format(v)),
                              if (widget.unit != null)
                                TextSpan(
                                  text: widget.unit,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w500,
                                    color: palette.foreground
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                            ],
                          ),
                          style: text.displaySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: palette.foreground,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            height: 1.05,
                          ),
                        ),
                        if (widget.label != null)
                          Text(
                            widget.label!.toUpperCase(),
                            style: text.labelMedium?.copyWith(
                              letterSpacing: 2,
                              color: palette.foreground.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints [NeuralGauge].
class NeuralGaugePainter extends CustomPainter {
  /// Creates the painter.
  NeuralGaugePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.palette,
    required this.thresholds,
    required this.sweep,
    required this.ticks,
    required this.rtl,
    this.strokeWidth,
  }) : super(repaint: value);

  /// Displayed value.
  final ValueListenable<double> value;

  /// Lower bound.
  final double min;

  /// Upper bound.
  final double max;

  /// Colors.
  final NeuralPalette palette;

  /// Sorted thresholds.
  final List<NeuralGaugeThreshold> thresholds;

  /// Sweep in radians.
  final double sweep;

  /// Tick count.
  final int ticks;

  /// Mirror.
  final bool rtl;

  /// Arc thickness override.
  final double? strokeWidth;

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _fill = Paint();
  Shader? _shader;
  Size _shaderSize = Size.zero;

  /// Fraction `0..1` of [v] between [min] and [max] (0 when the range is
  /// empty).
  double fraction(double v) {
    final span = max - min;
    if (!(span > 0) || !v.isFinite) return 0;
    return ((v - min) / span).clamp(0.0, 1.0);
  }

  /// Arc color at value [v]: the highest threshold at or below it, eased
  /// over a short band so color changes are not abrupt.
  Color? thresholdColor(double v) {
    if (thresholds.isEmpty) return null;
    Color? color;
    final band = (max - min).abs() * 0.04;
    for (final t in thresholds) {
      if (v >= t.value) {
        if (color == null || band <= 0) {
          color = t.color;
        } else {
          final k = ((v - t.value) / band).clamp(0.0, 1.0);
          color = Color.lerp(color, t.color, k);
        }
      }
    }
    return color;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final f = fraction(value.value);
    final center = size.center(Offset.zero);
    final sw = finiteOr(strokeWidth ?? size.shortestSide / 13, 8)
        .clamp(1.0, size.shortestSide / 5);
    final r = size.shortestSide / 2 - sw * 1.9;
    if (r <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: r);
    // The gap is centered at the bottom.
    final start = math.pi / 2 + (2 * math.pi - sweep) / 2;

    canvas.save();
    if (rtl) {
      // Mirror horizontally so the gauge fills from the right.
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    _stroke
      ..strokeWidth = sw
      ..shader = null
      ..maskFilter = null
      ..color = palette.track;
    canvas.drawArc(rect, start, sweep, false, _stroke);

    // Ticks outside the arc, lit up to the value.
    if (ticks > 0) {
      final inner = r + sw * 0.95;
      for (var i = 0; i <= ticks; i++) {
        final tf = i / ticks;
        final a = start + sweep * tf;
        final major = i % 5 == 0;
        // The liquid design keeps only the major ticks: calmer, purer.
        if (palette.isLiquid && !major) continue;
        final len = sw * (major ? 0.7 : 0.4);
        final lit = tf <= f + 1e-9 && f > 0;
        _stroke
          ..strokeWidth = major ? 1.6 : 1.0
          ..color = lit
              ? (thresholdColor(min + (max - min) * tf) ?? palette.accent)
                  .withValues(alpha: major ? 0.95 : 0.7)
              : palette.foreground.withValues(alpha: major ? 0.28 : 0.14);
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
            center + d * inner, center + d * (inner + len), _stroke);
      }
    }

    if (f > 0) {
      final valueSweep = sweep * f;
      final tc = thresholdColor(value.value);
      final glowK = palette.glowIntensity;
      final glowColor =
          tc ?? (palette.isLiquid ? palette.strokeAt(f) : palette.accent);
      if (glowK > 0) {
        _stroke
          ..strokeWidth = sw * 1.8
          ..color = glowColor.withValues(alpha: (0.38 * glowK).clamp(0, 1))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sw * 0.8);
        canvas.drawArc(rect, start, valueSweep, false, _stroke);
        _stroke.maskFilter = null;
      }
      _stroke.strokeWidth = sw;
      if (tc != null) {
        _stroke.color = tc;
      } else {
        if (_shader == null || _shaderSize != size) {
          _shaderSize = size;
          _shader = SweepGradient(
            startAngle: 0,
            endAngle: sweep,
            colors: palette.strokeColors,
            transform: GradientRotation(start),
          ).createShader(rect);
        }
        _stroke
          ..shader = _shader
          ..color = const Color(0xFF000000);
      }
      canvas.drawArc(rect, start, valueSweep, false, _stroke);
      _stroke.shader = null;

      // Glowing tip.
      final a = start + valueSweep;
      final tip = center + Offset(math.cos(a), math.sin(a)) * r;
      _fill.color = Color.lerp(glowColor, Colors.white, 0.7)!;
      canvas.drawCircle(tip, sw * 0.32, _fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(NeuralGaugePainter old) =>
      old.value != value ||
      old.min != min ||
      old.max != max ||
      old.palette != palette ||
      !_listEquals(old.thresholds, thresholds) ||
      old.sweep != sweep ||
      old.ticks != ticks ||
      old.rtl != rtl ||
      old.strokeWidth != strokeWidth;

  static bool _listEquals(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
