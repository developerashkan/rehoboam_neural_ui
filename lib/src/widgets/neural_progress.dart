import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';

/// The geometry of a [NeuralProgress].
enum NeuralProgressShape {
  /// A ring of synapse nodes.
  circular,

  /// A glowing bar.
  linear,
}

/// A neural loading / progress indicator.
///
/// * Determinate (`value` in `0..1`): the arc or bar fills smoothly toward
///   each new value, lighting synapse nodes as it passes them.
/// * Indeterminate (`value == null`): a comet of light circulates.
///
/// Fills clockwise / start-to-end, mirrored in right-to-left locales.
/// Exposes `value` to screen readers as a percentage, like Material's
/// progress indicators.
class NeuralProgress extends StatefulWidget {
  /// A circular indicator.
  const NeuralProgress({
    super.key,
    this.value,
    this.size = 56,
    this.strokeWidth,
    this.color,
    this.secondaryColor,
    this.trackColor,
    this.nodes,
    this.child,
    this.semanticsLabel,
    this.duration = const Duration(milliseconds: 450),
    this.animate = true,
  })  : shape = NeuralProgressShape.circular,
        height = 0;

  /// A horizontal bar. It stretches to the incoming width.
  const NeuralProgress.linear({
    super.key,
    this.value,
    this.height = 6,
    this.color,
    this.secondaryColor,
    this.trackColor,
    this.semanticsLabel,
    this.duration = const Duration(milliseconds: 450),
    this.animate = true,
  })  : shape = NeuralProgressShape.linear,
        size = 0,
        strokeWidth = null,
        nodes = 0,
        child = null;

  /// Progress `0..1`, or `null` for indeterminate.
  final double? value;

  /// Circular or linear.
  final NeuralProgressShape shape;

  /// Diameter (circular).
  final double size;

  /// Bar thickness (linear).
  final double height;

  /// Ring thickness. Defaults to `size / 14`.
  final double? strokeWidth;

  /// Fill color. Defaults to the theme accent.
  final Color? color;

  /// Gradient start color. Defaults to the theme secondary.
  final Color? secondaryColor;

  /// Unfilled track color.
  final Color? trackColor;

  /// Synapse nodes around the ring (circular, `0` hides them). Defaults
  /// to 12 in the neon design and none in the liquid design.
  final int? nodes;

  /// Optional content centered in the ring (e.g. a percentage).
  final Widget? child;

  /// Accessibility label. Defaults to "Loading".
  final String? semanticsLabel;

  /// How long the fill takes to reach a new [value].
  final Duration duration;

  /// Set to `false` to stop ambient motion.
  final bool animate;

  @override
  State<NeuralProgress> createState() => _NeuralProgressState();
}

class _NeuralProgressState extends State<NeuralProgress>
    with TickerProviderStateMixin {
  late final NeuralClock _clock = NeuralClock(this);
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.value == null ? 0 : unit(widget.value!),
  );
  double _from = 0;
  double _to = 0;
  bool _reduce = false;
  late final Animation<double> _curve =
      CurvedAnimation(parent: _fill, curve: Curves.easeOutCubic);

  /// The displayed (eased) progress.
  late final ValueNotifier<double> _shown =
      ValueNotifier(widget.value == null ? 0 : unit(widget.value!));

  @override
  void initState() {
    super.initState();
    _from = _to = _shown.value;
    _curve.addListener(() {
      _shown.value = _from + (_to - _from) * _curve.value;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotionOf(context);
    _clock.setRunning(widget.animate && !_reduce);
  }

  @override
  void didUpdateWidget(NeuralProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fill.duration = widget.duration;
    _clock.setRunning(widget.animate && !_reduce);
    final v = widget.value;
    if (v != null && v != oldWidget.value) {
      final target = unit(v);
      if (_reduce || widget.duration == Duration.zero) {
        _fill.stop();
        _from = _to = target;
        _shown.value = target;
      } else {
        _from = _shown.value;
        _to = target;
        _fill.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _clock.dispose();
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = NeuralPalette.of(
      context,
      accent: widget.color,
      secondary: widget.secondaryColor,
      track: widget.trackColor,
    );
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final determinate = widget.value != null;
    final painter = NeuralProgressPainter(
      clock: _clock,
      progress: _shown,
      determinate: determinate,
      shape: widget.shape,
      palette: palette,
      rtl: rtl,
      nodes: math.max(0, widget.nodes ?? (palette.isLiquid ? 0 : 12)),
      strokeWidth: widget.strokeWidth,
    );

    final Widget body;
    if (widget.shape == NeuralProgressShape.circular) {
      final size = finiteOr(widget.size, 56).clamp(0.0, double.maxFinite);
      body = SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: painter,
            child: widget.child == null
                ? null
                : Center(
                    child: Padding(
                      padding: EdgeInsets.all(size * 0.18),
                      child: FittedBox(child: widget.child),
                    ),
                  ),
          ),
        ),
      );
    } else {
      final h = finiteOr(widget.height, 6).clamp(1.0, 64.0);
      body = SizedBox(
        height: h * 3, // room for the glow
        width: double.infinity,
        child: RepaintBoundary(child: CustomPaint(painter: painter)),
      );
    }

    return Semantics(
      label: widget.semanticsLabel ?? 'Loading',
      value: determinate ? '${(unit(widget.value!) * 100).round()}%' : null,
      child: ExcludeSemantics(child: body),
    );
  }
}

/// Paints [NeuralProgress].
class NeuralProgressPainter extends CustomPainter {
  /// Creates the painter.
  NeuralProgressPainter({
    required this.clock,
    required this.progress,
    required this.determinate,
    required this.shape,
    required this.palette,
    required this.rtl,
    required this.nodes,
    this.strokeWidth,
  }) : super(repaint: Listenable.merge([clock, progress]));

  /// Elapsed seconds.
  final ValueListenable<double> clock;

  /// Displayed progress `0..1`.
  final ValueListenable<double> progress;

  /// Whether [progress] is meaningful.
  final bool determinate;

  /// Circular or linear.
  final NeuralProgressShape shape;

  /// Colors.
  final NeuralPalette palette;

  /// Mirror direction.
  final bool rtl;

  /// Ring nodes.
  final int nodes;

  /// Ring thickness override.
  final double? strokeWidth;

  final Paint _track = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _arc = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _glow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _dot = Paint();
  ui.Shader? _shader;
  Size _shaderSize = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    if (shape == NeuralProgressShape.circular) {
      _paintCircular(canvas, size);
    } else {
      _paintLinear(canvas, size);
    }
  }

  void _paintCircular(Canvas canvas, Size size) {
    final s = clock.value;
    final v = unit(progress.value);
    final center = size.center(Offset.zero);
    final sw = finiteOr(strokeWidth ?? size.shortestSide / 14, 4)
        .clamp(1.0, size.shortestSide / 4);
    final r = size.shortestSide / 2 - sw * 1.6;
    if (r <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: r);
    final dir = rtl ? -1.0 : 1.0;
    const top = -math.pi / 2;

    _track
      ..strokeWidth = sw
      ..color = palette.track;
    canvas.drawCircle(center, r, _track);

    if (_shader == null || _shaderSize != size) {
      _shaderSize = size;
      _shader = SweepGradient(
        colors: palette.isLiquid
            ? [...palette.strokeColors, palette.strokeColors.first]
            : [palette.secondary, palette.accent, palette.secondary],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    }

    double start;
    double sweep;
    if (determinate) {
      start = top;
      sweep = 2 * math.pi * v * dir;
    } else {
      final head = s * 2 * math.pi * 0.75;
      final len = 2 * math.pi * (0.2 + 0.12 * math.sin(s * 2.3));
      start = top + (head - len) * dir;
      sweep = len * dir;
    }

    if (sweep.abs() > 0.0001) {
      final glowK = palette.glowIntensity;
      if (glowK > 0) {
        _glow
          ..strokeWidth = sw * 2.2
          ..color = palette.accent.withValues(alpha: (0.35 * glowK).clamp(0, 1))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sw * 0.9);
        canvas.drawArc(rect, start, sweep, false, _glow);
      }
      _arc
        ..strokeWidth = sw
        ..shader = _shader
        ..color = const Color(0xFF000000);
      canvas.drawArc(rect, start, sweep, false, _arc);
    }

    // Synapse nodes sit just outside the ring.
    if (nodes > 0) {
      final nr = r + sw * 1.15;
      final dotR = math.max(1.0, sw * 0.28);
      for (var i = 0; i < nodes; i++) {
        final f = i / nodes;
        final a = top + 2 * math.pi * f * dir;
        final pos = center + Offset(math.cos(a), math.sin(a)) * nr;
        double lit;
        if (determinate) {
          lit = f <= v + 1e-6 && v > 0 ? 1 : 0;
          if (lit > 0 && (v - f) < 1 / nodes) {
            lit = 0.65 + 0.35 * math.sin(s * 6).abs(); // leading node pulses
          }
        } else {
          final rel = ((s * 0.75 - f) % 1 + 1) % 1; // distance behind head
          lit = rel < 0.32 ? 1 - rel / 0.32 : 0;
        }
        _dot.color = Color.lerp(palette.track, palette.accent, lit)!;
        canvas.drawCircle(pos, dotR * (1 + 0.5 * lit), _dot);
      }
    }
  }

  void _paintLinear(Canvas canvas, Size size) {
    final s = clock.value;
    final v = unit(progress.value);
    final h = size.height / 3;
    final y = size.height / 2;
    final w = size.width;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - h / 2, w, h),
      Radius.circular(h / 2),
    );
    _dot
      ..shader = null
      ..color = palette.track;
    canvas.drawRRect(track, _dot);

    double from;
    double to;
    if (determinate) {
      from = 0;
      to = w * v;
    } else {
      final cycle = (s * 0.55) % 1.0;
      final head = Curves.easeInOutCubic.transform(cycle) * 1.35;
      from = w * (head - 0.35).clamp(0.0, 1.0);
      to = w * head.clamp(0.0, 1.0);
    }
    if (to - from < 0.5) return;
    // Mirror in RTL.
    final left = rtl ? w - to : from;
    final right = rtl ? w - from : to;
    final fillRect = Rect.fromLTRB(left, y - h / 2, right, y + h / 2);
    final fill = RRect.fromRectAndRadius(fillRect, Radius.circular(h / 2));

    final glowK = palette.glowIntensity;
    if (glowK > 0) {
      _dot
        ..color = palette.accent.withValues(alpha: (0.4 * glowK).clamp(0, 1))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.9);
      canvas.drawRRect(fill, _dot);
      _dot.maskFilter = null;
    }
    if (_shader == null || _shaderSize != size) {
      _shaderSize = size;
      // Spans the whole track (start -> end), cached per size.
      _shader = ui.Gradient.linear(
        Offset(rtl ? w : 0, 0),
        Offset(rtl ? 0 : w, 0),
        palette.strokeColors,
        _evenStops(palette.strokeColors.length),
      );
    }
    _dot
      ..shader = _shader
      ..color = const Color(0xFF000000);
    canvas.drawRRect(fill, _dot);
    _dot.shader = null;

    // A data pulse travels along the filled part.
    final travel = (s * 0.8) % 1.0;
    final px = left + (right - left) * (rtl ? 1 - travel : travel);
    _dot.color =
        Colors.white.withValues(alpha: 0.55 * (1 - (2 * travel - 1).abs()));
    canvas.save();
    canvas.clipRRect(fill);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(px, y), width: h * 5, height: h),
      _dot,
    );
    canvas.restore();

    // Bright head.
    final headX = rtl ? left : right;
    _dot.color = Color.lerp(palette.accent, Colors.white, 0.6)!;
    canvas.drawCircle(
        Offset(headX - (rtl ? -h / 2 : h / 2), y), h * 0.42, _dot);
  }

  @override
  bool shouldRepaint(NeuralProgressPainter old) =>
      old.clock != clock ||
      old.progress != progress ||
      old.determinate != determinate ||
      old.shape != shape ||
      old.palette != palette ||
      old.rtl != rtl ||
      old.nodes != nodes ||
      old.strokeWidth != strokeWidth;
}

List<double> _evenStops(int n) =>
    [for (var i = 0; i < n; i++) n == 1 ? 0.0 : i / (n - 1)];
