import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';

/// A glowing sparkline / line chart.
///
/// * Draws itself in on first show and morphs smoothly when [data] changes
///   (series of different lengths are resampled, no jumps).
/// * Smooth curves use monotone cubic interpolation, so the line never
///   overshoots above the real maximum or below the minimum.
/// * Non-finite values (`NaN`, infinity) become gaps.
/// * Drag or hover to scrub: a cursor, a value tooltip, and [onScrub].
/// * Time flows with the reading direction (mirrored in RTL) unless
///   [mirrorInRtl] is `false`.
class NeuralSparkline extends StatefulWidget {
  /// Creates a sparkline.
  const NeuralSparkline({
    super.key,
    required this.data,
    this.height = 96,
    this.color,
    this.secondaryColor,
    this.strokeWidth = 2.4,
    this.smooth = true,
    this.fill = true,
    this.minY,
    this.maxY,
    this.showLatestDot = true,
    this.interactive = true,
    this.onScrub,
    this.valueFormatter,
    this.labelBuilder,
    this.mirrorInRtl = true,
    this.duration = const Duration(milliseconds: 700),
    this.semanticsLabel,
  });

  /// The series, oldest first.
  final List<double> data;

  /// Chart height (it stretches to the incoming width).
  final double height;

  /// Line color. Defaults to the theme accent.
  final Color? color;

  /// Gradient start color. Defaults to the theme secondary.
  final Color? secondaryColor;

  /// Line thickness.
  final double strokeWidth;

  /// Monotone cubic smoothing (`false` draws straight segments).
  final bool smooth;

  /// Gradient area under the line.
  final bool fill;

  /// Fixed lower bound (defaults to the data minimum).
  final double? minY;

  /// Fixed upper bound (defaults to the data maximum).
  final double? maxY;

  /// A pulsing dot on the latest point.
  final bool showLatestDot;

  /// Drag / hover scrubbing.
  final bool interactive;

  /// Called with the scrubbed index, and `null` when scrubbing ends.
  final ValueChanged<int?>? onScrub;

  /// Tooltip / semantics value text. Defaults to one decimal.
  final String Function(double value)? valueFormatter;

  /// Optional tooltip prefix per index (e.g. a date).
  final String Function(int index)? labelBuilder;

  /// Mirror the time axis in right-to-left locales.
  final bool mirrorInRtl;

  /// Draw-in / morph animation length.
  final Duration duration;

  /// Accessibility label. Defaults to "Trend".
  final String? semanticsLabel;

  @override
  State<NeuralSparkline> createState() => _NeuralSparklineState();
}

class _NeuralSparklineState extends State<NeuralSparkline>
    with TickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
  late final NeuralClock _clock = NeuralClock(this);
  final ValueNotifier<int?> _scrub = ValueNotifier(null);

  List<double> _from = const [];
  List<double> _to = const [];
  bool _reveal = true; // first animation reveals instead of morphing
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    _to = List.of(widget.data);
    _from = _to;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = reduceMotionOf(context);
    final first = !_anim.isAnimating && _anim.value == 0 && _reveal;
    _reduce = reduce;
    if (first) {
      if (reduce || widget.duration == Duration.zero) {
        _anim.value = 1;
        _reveal = false;
      } else {
        _anim.forward().whenCompleteOrCancel(() => _reveal = false);
      }
    }
    _clock.setRunning(widget.showLatestDot && !_reduce);
  }

  @override
  void didUpdateWidget(NeuralSparkline oldWidget) {
    super.didUpdateWidget(oldWidget);
    _anim.duration = widget.duration;
    _clock.setRunning(widget.showLatestDot && !_reduce);
    if (!_sameData(_to, widget.data)) {
      // Morph from what is on screen now to the new series.
      final current = _displayed(_curve.value);
      _reveal = false;
      _to = List.of(widget.data);
      _from = resample(current, _to.length);
      if (_reduce || widget.duration == Duration.zero) {
        _anim.value = 1;
      } else {
        _anim.forward(from: 0);
      }
      final s = _scrub.value;
      if (s != null && s >= _to.length) _scrub.value = null;
    }
  }

  // Compares against our own copy, so a list mutated in place is still
  // detected and an unchanged rebuild does not restart the animation.
  static bool _sameData(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i] && !(a[i].isNaN && b[i].isNaN)) return false;
    }
    return true;
  }

  List<double> _displayed(double t) {
    if (_reveal || t >= 1) return _to;
    return [
      for (var i = 0; i < _to.length; i++) _lerpGap(_from[i], _to[i], t),
    ];
  }

  static double _lerpGap(double a, double b, double t) {
    if (!b.isFinite) return b;
    if (!a.isFinite) return b;
    return a + (b - a) * t;
  }

  /// Linearly resamples [src] to [n] points (gaps preserved when possible).
  static List<double> resample(List<double> src, int n) {
    if (n <= 0) return const [];
    if (src.isEmpty) return List.filled(n, double.nan);
    if (src.length == n) return List.of(src);
    if (src.length == 1) return List.filled(n, src.first);
    return [
      for (var i = 0; i < n; i++)
        () {
          final x = n == 1 ? 0.0 : i * (src.length - 1) / (n - 1);
          final lo = x.floor().clamp(0, src.length - 1);
          final hi = math.min(lo + 1, src.length - 1);
          final f = x - lo;
          final a = src[lo];
          final b = src[hi];
          if (!a.isFinite) return b;
          if (!b.isFinite) return a;
          return a + (b - a) * f;
        }(),
    ];
  }

  @override
  void dispose() {
    _curve.dispose();
    _anim.dispose();
    _clock.dispose();
    _scrub.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      widget.valueFormatter?.call(v) ?? v.toStringAsFixed(1);

  int? _indexAt(double dx, double width, bool mirror) {
    final n = _to.length;
    if (n == 0 || width <= 0) return null;
    var f = (dx / width).clamp(0.0, 1.0);
    if (mirror) f = 1 - f;
    return n == 1 ? 0 : (f * (n - 1)).round();
  }

  void _setScrub(int? i) {
    if (_scrub.value == i) return;
    _scrub.value = i;
    widget.onScrub?.call(i);
  }

  @override
  Widget build(BuildContext context) {
    final palette = NeuralPalette.of(
      context,
      accent: widget.color,
      secondary: widget.secondaryColor,
    );
    final mirror = widget.mirrorInRtl &&
        Directionality.maybeOf(context) == TextDirection.rtl;
    final h = finiteOr(widget.height, 96).clamp(8.0, 4000.0);
    final finite = widget.data.where((v) => v.isFinite).toList();
    final semanticsValue = finite.isEmpty
        ? 'No data'
        : 'Latest ${_fmt(finite.last)}, '
            'min ${_fmt(finite.reduce(math.min))}, '
            'max ${_fmt(finite.reduce(math.max))}';
    final theme = Theme.of(context);

    return Semantics(
      label: widget.semanticsLabel ?? 'Trend',
      value: semanticsValue,
      child: ExcludeSemantics(
        child: SizedBox(
          height: h,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, c) {
              final width = c.maxWidth.isFinite ? c.maxWidth : 300.0;
              Widget chart = RepaintBoundary(
                child: CustomPaint(
                  size: Size(width, h),
                  painter: NeuralSparklinePainter(
                    animation: _curve,
                    clock: _clock,
                    scrub: _scrub,
                    from: _from,
                    to: _to,
                    reveal: _reveal,
                    palette: palette,
                    strokeWidth:
                        finiteOr(widget.strokeWidth, 2.4).clamp(0.5, 16),
                    smooth: widget.smooth,
                    fill: widget.fill,
                    minY: widget.minY,
                    maxY: widget.maxY,
                    showLatestDot: widget.showLatestDot,
                    mirror: mirror,
                  ),
                ),
              );
              if (!widget.interactive) return chart;
              chart = MouseRegion(
                onHover: (e) =>
                    _setScrub(_indexAt(e.localPosition.dx, width, mirror)),
                onExit: (_) => _setScrub(null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // The cursor appears where the finger lands, not after
                  // the drag slop.
                  dragStartBehavior: DragStartBehavior.down,
                  onHorizontalDragStart: (d) =>
                      _setScrub(_indexAt(d.localPosition.dx, width, mirror)),
                  onHorizontalDragUpdate: (d) =>
                      _setScrub(_indexAt(d.localPosition.dx, width, mirror)),
                  onHorizontalDragEnd: (_) => _setScrub(null),
                  onHorizontalDragCancel: () => _setScrub(null),
                  onTapDown: (d) =>
                      _setScrub(_indexAt(d.localPosition.dx, width, mirror)),
                  onTapUp: (_) => _setScrub(null),
                  child: chart,
                ),
              );
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  chart,
                  ValueListenableBuilder<int?>(
                    valueListenable: _scrub,
                    builder: (context, i, _) {
                      if (i == null || i >= _to.length) {
                        return const SizedBox.shrink();
                      }
                      final v = _to[i];
                      final n = _to.length;
                      var fx = n == 1 ? 0.5 : i / (n - 1);
                      if (mirror) fx = 1 - fx;
                      final prefix = widget.labelBuilder?.call(i);
                      final text = v.isFinite ? _fmt(v) : '–';
                      return Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Align(
                          alignment: Alignment(fx * 2 - 1, -1),
                          child: IgnorePointer(
                            child: Material(
                              type: MaterialType.transparency,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: palette.isDark
                                      ? const Color(0xE6101422)
                                      : const Color(0xF2FFFFFF),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        palette.accent.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    prefix == null ? text : '$prefix  $text',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: palette.foreground,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Paints [NeuralSparkline].
class NeuralSparklinePainter extends CustomPainter {
  /// Creates the painter. Series are read lazily so the painter instance
  /// survives animation frames.
  NeuralSparklinePainter({
    required this.animation,
    required this.clock,
    required this.scrub,
    required this.from,
    required this.to,
    required this.reveal,
    required this.palette,
    required this.strokeWidth,
    required this.smooth,
    required this.fill,
    required this.showLatestDot,
    required this.mirror,
    this.minY,
    this.maxY,
  }) : super(repaint: Listenable.merge([animation, clock, scrub]));

  /// Draw-in / morph progress.
  final Animation<double> animation;

  /// Pulse clock.
  final ValueListenable<double> clock;

  /// Scrubbed index.
  final ValueListenable<int?> scrub;

  /// Series before the morph.
  final List<double> from;

  /// Series after the morph.
  final List<double> to;

  /// Whether the animation is the first reveal.
  final bool reveal;

  /// Colors.
  final NeuralPalette palette;

  /// Line width.
  final double strokeWidth;

  /// Smooth curve.
  final bool smooth;

  /// Area fill.
  final bool fill;

  /// Pulsing latest point.
  final bool showLatestDot;

  /// Mirror x.
  final bool mirror;

  /// Fixed bounds.
  final double? minY;

  /// Fixed bounds.
  final double? maxY;

  final Path _line = Path();
  final Path _area = Path();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _paint = Paint();
  List<double> _ys = const [];
  List<double> _xs = const [];
  Size _cachedSize = Size.zero;
  double _cachedT = -1;
  Object? _cachedData;
  ui.Shader? _lineShader;
  ui.Shader? _areaShader;

  /// Monotone cubic (Fritsch–Carlson) tangents for points [xs], [ys].
  static List<double> monotoneTangents(List<double> xs, List<double> ys) {
    final n = xs.length;
    final m = List<double>.filled(n, 0);
    if (n < 2) return m;
    final d = List<double>.filled(n - 1, 0);
    for (var i = 0; i < n - 1; i++) {
      final dx = xs[i + 1] - xs[i];
      d[i] = dx == 0 ? 0 : (ys[i + 1] - ys[i]) / dx;
    }
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (var i = 1; i < n - 1; i++) {
      m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    }
    for (var i = 0; i < n - 1; i++) {
      if (d[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
        continue;
      }
      final a = m[i] / d[i];
      final b = m[i + 1] / d[i];
      final h = a * a + b * b;
      if (h > 9) {
        final t = 3 / math.sqrt(h);
        m[i] = t * a * d[i];
        m[i + 1] = t * b * d[i];
      }
    }
    return m;
  }

  void _build(Size size, double t) {
    final a = from;
    final b = to;
    final isReveal = reveal;
    final n = b.length;
    final ys = List<double>.filled(n, double.nan);
    for (var i = 0; i < n; i++) {
      final target = b[i];
      if (isReveal || t >= 1 || i >= a.length) {
        ys[i] = target;
      } else {
        final src = a[i];
        ys[i] = !target.isFinite
            ? target
            : (!src.isFinite ? target : src + (target - src) * t);
      }
    }
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final v in b) {
      if (v.isFinite) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (minY != null && minY!.isFinite) lo = minY!;
    if (maxY != null && maxY!.isFinite) hi = maxY!;
    final pad = strokeWidth * 2 + 6;
    final top = pad + 18; // tooltip headroom
    final bottom = size.height - pad;
    final usable = math.max(1.0, bottom - top);
    final span = (hi - lo).abs() < 1e-12 ? 1.0 : hi - lo;
    final flat = !(hi > lo);
    final xs = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      var fx = n == 1 ? 0.5 : i / (n - 1);
      if (mirror) fx = 1 - fx;
      xs[i] = pad + fx * (size.width - pad * 2);
      final v = ys[i];
      ys[i] = !v.isFinite
          ? double.nan
          : flat
              ? top + usable / 2
              : bottom - ((v - lo) / span).clamp(-0.5, 1.5) * usable;
    }
    _xs = xs;
    _ys = ys;

    _line.reset();
    _area.reset();
    // Each run of finite points is its own sub-path.
    var i = 0;
    while (i < n) {
      while (i < n && ys[i].isNaN) {
        i++;
      }
      final startIdx = i;
      while (i < n && !ys[i].isNaN) {
        i++;
      }
      final end = i; // exclusive
      if (end - startIdx == 0) continue;
      final rx = xs.sublist(startIdx, end);
      final ry = ys.sublist(startIdx, end);
      final m = smooth && rx.length > 2 ? monotoneTangents(rx, ry) : null;
      _line.moveTo(rx.first, ry.first);
      if (rx.length == 1) {
        _line.lineTo(rx.first + 0.01, ry.first); // a dot still shows
      } else {
        _addCurve(_line, rx, ry, m);
      }
      if (fill && rx.length > 1) {
        _area
          ..moveTo(rx.first, bottom + pad)
          ..lineTo(rx.first, ry.first);
        _addCurve(_area, rx, ry, m);
        _area
          ..lineTo(rx.last, bottom + pad)
          ..close();
      }
    }
  }

  /// Appends the run from its first point (the current point of [p]).
  static void _addCurve(
      Path p, List<double> rx, List<double> ry, List<double>? m) {
    if (m != null) {
      for (var k = 0; k < rx.length - 1; k++) {
        final dx = (rx[k + 1] - rx[k]) / 3;
        p.cubicTo(rx[k] + dx, ry[k] + m[k] * dx, rx[k + 1] - dx,
            ry[k + 1] - m[k + 1] * dx, rx[k + 1], ry[k + 1]);
      }
    } else {
      for (var k = 1; k < rx.length; k++) {
        p.lineTo(rx[k], ry[k]);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final t = animation.value;
    final data = to;
    final isReveal = reveal;
    // Rebuild geometry only when the data, size or morph frame changed: the
    // pulse clock alone repaints from the cached paths.
    final morphT = isReveal ? 1.0 : t;
    if (_cachedSize != size ||
        _cachedT != morphT ||
        !identical(_cachedData, data)) {
      _build(size, morphT);
      _cachedSize = size;
      _cachedT = morphT;
      _cachedData = data;
      _lineShader = ui.Gradient.linear(
        Offset(mirror ? size.width : 0, 0),
        Offset(mirror ? 0 : size.width, 0),
        palette.strokeColors,
        [
          for (var i = 0; i < palette.strokeColors.length; i++)
            i / (palette.strokeColors.length - 1),
        ],
      );
      final areaColor =
          palette.isLiquid ? palette.strokeAt(0.6) : palette.accent;
      _areaShader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [
          areaColor.withValues(alpha: palette.isDark ? 0.3 : 0.18),
          areaColor.withValues(alpha: 0),
        ],
      );
    }
    if (_xs.isEmpty) {
      _stroke
        ..shader = null
        ..strokeWidth = 1
        ..color = palette.track;
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), _stroke);
      return;
    }

    canvas.save();
    if (isReveal && t < 1) {
      // Draw-in: reveal along the time axis.
      final w = size.width * t;
      canvas.clipRect(mirror
          ? Rect.fromLTRB(size.width - w, 0, size.width, size.height)
          : Rect.fromLTWH(0, 0, w, size.height));
    }
    if (fill) {
      _paint
        ..shader = _areaShader
        ..color = const Color(0xFF000000);
      canvas.drawPath(_area, _paint);
    }
    final glowK = palette.glowIntensity;
    if (glowK > 0) {
      _stroke
        ..shader = null
        ..strokeWidth = strokeWidth * 3
        ..color = palette.accent.withValues(alpha: (0.35 * glowK).clamp(0, 1))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * 1.6);
      canvas.drawPath(_line, _stroke);
      _stroke.maskFilter = null;
    }
    _stroke
      ..strokeWidth = strokeWidth
      ..shader = _lineShader
      ..color = const Color(0xFF000000);
    canvas.drawPath(_line, _stroke);
    _stroke.shader = null;
    canvas.restore();

    // Latest point pulse.
    final last = _lastFinite();
    if (showLatestDot && last != null && (!isReveal || t >= 1)) {
      final p = Offset(_xs[last], _ys[last]);
      final pulse = (clock.value * 0.8) % 1.0;
      _paint
        ..shader = null
        ..color = palette.accent.withValues(alpha: 0.45 * (1 - pulse));
      canvas.drawCircle(p, strokeWidth * (1.5 + 4 * pulse), _paint);
      _paint.color = palette.accent;
      canvas.drawCircle(p, strokeWidth * 1.5, _paint);
      _paint.color = Colors.white;
      canvas.drawCircle(p, strokeWidth * 0.7, _paint);
    }

    // Scrub cursor.
    final si = scrub.value;
    if (si != null && si < _xs.length) {
      final x = _xs[si];
      _stroke
        ..strokeWidth = 1
        ..color = palette.foreground.withValues(alpha: 0.35);
      canvas.drawLine(Offset(x, 18), Offset(x, size.height), _stroke);
      final y = _ys[si];
      if (!y.isNaN) {
        _paint.color = palette.surface;
        canvas.drawCircle(Offset(x, y), strokeWidth * 2.2, _paint);
        _stroke
          ..strokeWidth = strokeWidth
          ..color = palette.accent;
        canvas.drawCircle(Offset(x, y), strokeWidth * 2.2, _stroke);
      }
    }
  }

  int? _lastFinite() {
    for (var i = _ys.length - 1; i >= 0; i--) {
      if (!_ys[i].isNaN) return i;
    }
    return null;
  }

  @override
  bool shouldRepaint(NeuralSparklinePainter old) =>
      old.animation != animation ||
      old.palette != palette ||
      old.strokeWidth != strokeWidth ||
      old.smooth != smooth ||
      old.fill != fill ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.showLatestDot != showLatestDot ||
      old.mirror != mirror ||
      !identical(old.to, to) ||
      !identical(old.from, from) ||
      old.reveal != reveal;
}
