import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';

/// The phase of a [NeuralScanRing].
enum NeuralScanStatus {
  /// Waiting: a calm, slowly turning ring.
  idle,

  /// Working: radar sweep, scan line and progress arc.
  scanning,

  /// Verified: the ring locks, a check mark draws in, a ripple bursts.
  success,

  /// Rejected: the ring flashes the error color, a cross draws in, shakes.
  failure,
}

/// A scanning / verification ring for biometrics, uploads, pairing or any
/// "checking..." moment.
///
/// Put a face, fingerprint icon or file thumbnail in [child]. Drive
/// [status] and, optionally, [progress]; [onResolved] fires once the
/// success / failure animation has finished, which is the right moment to
/// navigate on. Status changes are announced to screen readers.
class NeuralScanRing extends StatefulWidget {
  /// Creates a scan ring.
  const NeuralScanRing({
    super.key,
    this.status = NeuralScanStatus.scanning,
    this.progress,
    this.size = 180,
    this.child,
    this.color,
    this.successColor,
    this.errorColor,
    this.onResolved,
    this.semanticsLabel,
    this.statusLabels = const {
      NeuralScanStatus.idle: 'Ready to scan',
      NeuralScanStatus.scanning: 'Scanning',
      NeuralScanStatus.success: 'Verified',
      NeuralScanStatus.failure: 'Verification failed',
    },
  });

  /// Current phase.
  final NeuralScanStatus status;

  /// Scan progress `0..1`, or `null` for an indeterminate scan.
  final double? progress;

  /// Diameter.
  final double size;

  /// Content inside the ring (clipped to a circle).
  final Widget? child;

  /// Scanning color. Defaults to the theme accent.
  final Color? color;

  /// Success color. Defaults to the neural theme's success green.
  final Color? successColor;

  /// Failure color. Defaults to `ColorScheme.error`.
  final Color? errorColor;

  /// Called after the success / failure animation completes.
  final ValueChanged<NeuralScanStatus>? onResolved;

  /// Overrides the announced label.
  final String? semanticsLabel;

  /// Announced text per status (localize these).
  final Map<NeuralScanStatus, String> statusLabels;

  @override
  State<NeuralScanRing> createState() => _NeuralScanRingState();
}

/// Mutable values the painter reads every frame.
class ScanRingState {
  /// Displayed (eased) progress.
  double progress = 0;
}

class _NeuralScanRingState extends State<NeuralScanRing>
    with TickerProviderStateMixin {
  late final NeuralClock _clock = NeuralClock(this)..onTick = _onTick;
  late final AnimationController _resolve = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
    // Created already resolved (no status notification, so no callback
    // fires during initState).
    value: _resolved ? 1 : 0,
  )..addStatusListener(_onResolveStatus);
  final ScanRingState _live = ScanRingState();
  bool _reduce = false;
  bool _silent = false; // set while jumping the animation without callbacks

  bool get _resolved =>
      widget.status == NeuralScanStatus.success ||
      widget.status == NeuralScanStatus.failure;

  double get _targetProgress {
    if (_resolved) return 1;
    final p = widget.progress;
    return p == null ? 0 : unit(p);
  }

  @override
  void initState() {
    super.initState();
    _live.progress = _targetProgress;
  }

  void _onTick(double dt) {
    final k = 1 - math.exp(-dt * 7);
    _live.progress += (_targetProgress - _live.progress) * k;
  }

  void _onResolveStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && _resolved && mounted && !_silent) {
      widget.onResolved?.call(widget.status);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotionOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(NeuralScanRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      if (_resolved) {
        if (_reduce) {
          _silent = true;
          _resolve.value = 1;
          _silent = false;
          // Still notify, after this frame (never during build).
          final status = widget.status;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.status == status) {
              widget.onResolved?.call(status);
            }
          });
        } else {
          _resolve.forward(from: 0);
        }
      } else {
        _resolve.value = 0;
      }
    }
    _sync();
  }

  void _sync() {
    final running = !_reduce;
    _clock.setRunning(running);
    if (!running) {
      _live.progress = _targetProgress;
      _clock.advance(0);
    }
  }

  @override
  void dispose() {
    _resolve.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = NeuralPalette.of(context, accent: widget.color);
    // Liquid design: an iridescent violet-azure scan instead of primary.
    final palette = widget.color == null && base.isLiquid
        ? NeuralPalette.of(context, accent: base.strokeAt(0.78))
        : base;
    final size = finiteOr(widget.size, 180).clamp(0.0, double.maxFinite);
    final resolveColor = switch (widget.status) {
      NeuralScanStatus.success => widget.successColor ?? palette.success,
      NeuralScanStatus.failure => widget.errorColor ?? palette.error,
      _ => palette.accent,
    };
    final label = widget.semanticsLabel ??
        widget.statusLabels[widget.status] ??
        widget.status.name;
    final p = widget.progress;
    final value = widget.status == NeuralScanStatus.scanning && p != null
        ? '${(unit(p) * 100).round()}%'
        : null;

    Widget ring = SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: CustomPaint(
          foregroundPainter: NeuralScanPainter(
            clock: _clock,
            resolve: _resolve,
            live: _live,
            status: widget.status,
            determinate: p != null || _resolved,
            palette: palette,
            resolveColor: resolveColor,
          ),
          child: widget.child == null
              ? null
              : Padding(
                  padding: EdgeInsets.all(size * 0.2),
                  child: ClipOval(child: Center(child: widget.child)),
                ),
        ),
      ),
    );

    if (widget.status == NeuralScanStatus.failure && !_reduce) {
      ring = AnimatedBuilder(
        animation: _resolve,
        builder: (context, child) {
          final t = _resolve.value;
          final dx = math.sin(t * math.pi * 7) * (1 - t) * size * 0.035;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: ring,
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      value: value,
      child: ExcludeSemantics(child: ring),
    );
  }
}

/// Paints [NeuralScanRing].
class NeuralScanPainter extends CustomPainter {
  /// Creates the painter.
  NeuralScanPainter({
    required this.clock,
    required this.resolve,
    required this.live,
    required this.status,
    required this.determinate,
    required this.palette,
    required this.resolveColor,
  }) : super(repaint: Listenable.merge([clock, resolve]));

  /// Frame clock.
  final ValueListenable<double> clock;

  /// Success / failure animation.
  final Animation<double> resolve;

  /// Eased progress.
  final ScanRingState live;

  /// Phase.
  final NeuralScanStatus status;

  /// Whether to draw a progress arc rather than spinners.
  final bool determinate;

  /// Colors.
  final NeuralPalette palette;

  /// Target color of the resolve animation.
  final Color resolveColor;

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _fill = Paint();
  final Path _mark = Path();
  ui.Shader? _radar;
  ui.Shader? _scan;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final s = clock.value;
    final rt = Curves.easeOutCubic.transform(resolve.value.clamp(0.0, 1.0));
    final resolved = status == NeuralScanStatus.success ||
        status == NeuralScanStatus.failure;
    final scanning = status == NeuralScanStatus.scanning;
    final c = size.center(Offset.zero);
    final big = size.shortestSide / 2;
    final color = resolved
        ? Color.lerp(palette.accent, resolveColor, rt)!
        : palette.accent;
    final activity = scanning ? 1.0 : (resolved ? 1 - rt : 0.25);
    final glowK = palette.glowIntensity;

    // 1. Outer tick ring, turning while active.
    const ticks = 72;
    final tickSpin = s * 0.25 * activity;
    final tickR0 = big * 0.92;
    for (var i = 0; i < ticks; i++) {
      final f = i / ticks;
      final a = -math.pi / 2 + f * 2 * math.pi + tickSpin;
      final major = i % 6 == 0;
      final lit = determinate ? f <= live.progress + 1e-6 : (i % 12 < 3);
      _stroke
        ..strokeWidth = major ? 2 : 1.2
        ..color = lit
            ? color.withValues(alpha: major ? 0.95 : 0.7)
            : palette.foreground.withValues(alpha: major ? 0.22 : 0.1);
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * tickR0,
          c + d * (tickR0 + big * (major ? 0.07 : 0.04)), _stroke);
    }

    // 2. Progress arc / spinners.
    final arcR = big * 0.84;
    final arcRect = Rect.fromCircle(center: c, radius: arcR);
    final sw = math.max(2.0, big * 0.035);
    _stroke
      ..strokeWidth = sw
      ..color = palette.track;
    canvas.drawCircle(c, arcR, _stroke);
    double sweep;
    double start;
    if (determinate) {
      start = -math.pi / 2;
      sweep = 2 * math.pi * live.progress.clamp(0.0, 1.0);
    } else {
      start = -math.pi / 2 + s * 2.2;
      sweep =
          math.pi * (0.35 + 0.15 * math.sin(s * 1.7)) * (0.4 + 0.6 * activity);
    }
    if (sweep > 0.001) {
      if (glowK > 0) {
        _stroke
          ..strokeWidth = sw * 2.4
          ..color = color.withValues(alpha: (0.4 * glowK).clamp(0, 1))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sw);
        canvas.drawArc(arcRect, start, sweep, false, _stroke);
        _stroke.maskFilter = null;
      }
      _stroke
        ..strokeWidth = sw
        ..color = color;
      canvas.drawArc(arcRect, start, sweep, false, _stroke);
      if (!determinate) {
        canvas.drawArc(arcRect, start + math.pi, sweep * 0.6, false, _stroke);
      }
    }

    // 3. Radar sweep and scan line inside the lens.
    final lensR = big * 0.76;
    if (activity > 0.01) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(
          Rect.fromCircle(center: c, radius: lensR), Radius.circular(lensR)));
      _radar ??= ui.Gradient.sweep(
        Offset.zero,
        [
          palette.accent.withValues(alpha: 0),
          palette.accent.withValues(alpha: 0),
          palette.accent.withValues(alpha: 0.32),
        ],
        const [0, 0.7, 1],
      );
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(s * 1.6);
      _fill
        ..shader = _radar
        ..color = Color.fromRGBO(0, 0, 0, activity.clamp(0.0, 1.0));
      canvas.drawCircle(Offset.zero, lensR, _fill);
      canvas.restore();

      if (scanning) {
        // Ping-pong scan line with a soft trail.
        final phase = (s * 0.55) % 2.0;
        final down = phase < 1;
        final f = Curves.easeInOutSine.transform(down ? phase : 2 - phase);
        final y = c.dy - lensR + f * lensR * 2;
        _scan ??= ui.Gradient.linear(
          Offset.zero,
          const Offset(0, 1),
          [
            palette.accent.withValues(alpha: 0),
            palette.accent.withValues(alpha: 0.35)
          ],
        );
        canvas.save();
        canvas.translate(
            c.dx - lensR, down ? y - lensR * 0.35 : y + lensR * 0.35);
        canvas.scale(lensR * 2, down ? lensR * 0.35 : -lensR * 0.35);
        _fill
          ..shader = _scan
          ..color = const Color(0xFF000000);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), _fill);
        canvas.restore();
        _fill
          ..shader = null
          ..color = Color.lerp(palette.accent, Colors.white, 0.45)!;
        canvas.drawRect(
            Rect.fromLTWH(c.dx - lensR, y - 1, lensR * 2, 2), _fill);
      }
      canvas.restore();
    }
    _fill.shader = null;

    // 4. Resolution: disc, mark and ripple.
    if (resolved && rt > 0) {
      _fill.color = resolveColor.withValues(alpha: 0.88 * rt);
      canvas.drawCircle(c, lensR * (0.6 + 0.4 * rt), _fill);

      // Ripple burst.
      final ripple = resolve.value;
      _stroke
        ..strokeWidth = sw * (1 - ripple) + 0.5
        ..color = resolveColor.withValues(alpha: 0.6 * (1 - ripple));
      canvas.drawCircle(c, big * (0.84 + 0.16 * ripple), _stroke);

      _mark.reset();
      final m = lensR * 0.42;
      if (status == NeuralScanStatus.success) {
        _mark
          ..moveTo(c.dx - m * 0.9, c.dy + m * 0.02)
          ..lineTo(c.dx - m * 0.28, c.dy + m * 0.6)
          ..lineTo(c.dx + m * 0.95, c.dy - m * 0.62);
      } else {
        _mark
          ..moveTo(c.dx - m * 0.62, c.dy - m * 0.62)
          ..lineTo(c.dx + m * 0.62, c.dy + m * 0.62)
          ..moveTo(c.dx + m * 0.62, c.dy - m * 0.62)
          ..lineTo(c.dx - m * 0.62, c.dy + m * 0.62);
      }
      _stroke
        ..strokeWidth = math.max(2.5, lensR * 0.11)
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white;
      final draw = ((resolve.value - 0.25) / 0.6).clamp(0.0, 1.0);
      if (draw >= 1) {
        canvas.drawPath(_mark, _stroke);
      } else if (draw > 0) {
        // Draw the mark progressively along its contours.
        final metrics = _mark.computeMetrics().toList();
        final total = metrics.fold<double>(0, (a, b) => a + b.length);
        var left = total * draw;
        for (final pm in metrics) {
          if (left <= 0) break;
          final len = math.min(left, pm.length);
          canvas.drawPath(pm.extractPath(0, len), _stroke);
          left -= len;
        }
      }
    }
  }

  @override
  bool shouldRepaint(NeuralScanPainter old) =>
      old.clock != clock ||
      old.resolve != resolve ||
      old.live != live ||
      old.status != status ||
      old.determinate != determinate ||
      old.palette != palette ||
      old.resolveColor != resolveColor;
}
