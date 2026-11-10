import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';
import 'neural_shaders.dart';

/// Shared plumbing for shader-driven widgets: loads [shaderKind] once,
/// owns the [ui.FragmentShader], and runs a [NeuralClock] that honors
/// reduced motion.
mixin _ShaderHost<T extends StatefulWidget> on State<T>, TickerProvider {
  NeuralShader get shaderKind;
  ui.FragmentShader? shader;
  late final NeuralClock clock = NeuralClock(this);
  bool reduceMotion = false;

  void initShader() {
    final ready = NeuralShaders.cached(shaderKind);
    if (ready != null) {
      shader = ready.fragmentShader();
      return;
    }
    NeuralShaders.load(shaderKind).then((p) {
      if (mounted && p != null && shader == null) {
        setState(() => shader = p.fragmentShader());
      }
    });
  }

  void disposeShader() {
    clock.dispose();
    shader?.dispose();
  }
}

/// Smoothly follows a target value inside a clock tick.
double _follow(double current, double target, double dt, double rate) =>
    current + (target - current) * (1 - math.exp(-dt * rate));

/// A voice waveform of translucent light ribbons, pinned at both ends,
/// whose amplitude follows [level]. Rest it at a gentle idle wave, or pass
/// `active: false` for a flat line.
class NeuralWaveform extends StatefulWidget {
  /// Creates a waveform. It stretches to the incoming width.
  const NeuralWaveform({
    super.key,
    this.level = 0,
    this.active = true,
    this.height = 96,
    this.colors,
    this.semanticsLabel,
  });

  /// Voice level `0..1` (raw readings are fine; smoothed internally).
  final double level;

  /// Whether the voice channel is open (idle wave) or closed (flat).
  final bool active;

  /// Height.
  final double height;

  /// Four ribbon colors. Defaults to the theme spectrum.
  final List<Color>? colors;

  /// Accessibility label.
  final String? semanticsLabel;

  @override
  State<NeuralWaveform> createState() => _NeuralWaveformState();
}

/// Live waveform values.
class WaveMotion {
  /// Flow phase.
  double phase = 0;

  /// Smoothed level.
  double level = 0;

  /// Smoothed resting amplitude.
  double idle = 0.08;
}

class _NeuralWaveformState extends State<NeuralWaveform>
    with SingleTickerProviderStateMixin, _ShaderHost {
  @override
  NeuralShader get shaderKind => NeuralShader.liquidWave;
  final WaveMotion _m = WaveMotion();

  @override
  void initState() {
    super.initState();
    initShader();
    _m.idle = widget.active ? 0.08 : 0;
    clock.onTick = (dt) {
      _m.level = _follow(_m.level, unit(widget.level), dt, 10);
      _m.idle = _follow(_m.idle, widget.active ? 0.08 : 0.0, dt, 4);
      _m.phase += dt * (1.6 + 3.2 * _m.level);
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion = reduceMotionOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(NeuralWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    clock.setRunning(!reduceMotion);
    if (reduceMotion) {
      _m
        ..level = unit(widget.level)
        ..idle = widget.active ? 0.08 : 0;
      clock.advance(0);
    }
  }

  @override
  void dispose() {
    disposeShader();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = NeuralPalette.of(context);
    final colors = widget.colors ?? palette.spectrum;
    final four = [for (var i = 0; i < 4; i++) colors[i % colors.length]];
    return Semantics(
      label: widget.semanticsLabel ??
          (widget.active ? 'Voice active' : 'Voice idle'),
      image: true,
      child: SizedBox(
        height: finiteOr(widget.height, 96).clamp(8.0, 2000.0),
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _WavePainter(
              clock: clock,
              motion: _m,
              shader: shader,
              colors: four,
              dark: palette.isDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.clock,
    required this.motion,
    required this.shader,
    required this.colors,
    required this.dark,
  }) : super(repaint: clock);

  final ValueListenable<double> clock;
  final WaveMotion motion;
  final ui.FragmentShader? shader;
  final List<Color> colors;
  final bool dark;
  final Paint _paint = Paint();
  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final s = shader;
    if (s != null) {
      var i = 0;
      void f(double v) => s.setFloat(i++, v);
      f(size.width);
      f(size.height);
      f(motion.phase);
      f(motion.level);
      f(motion.idle);
      for (final c in colors) {
        f(c.r);
        f(c.g);
        f(c.b);
        f(1);
      }
      f(dark ? 1 : 0);
      _paint
        ..shader = s
        ..color = const Color(0xFF000000);
      canvas.drawRect(Offset.zero & size, _paint);
      _paint.shader = null;
      return;
    }
    // Fallback: four stroked sine ribbons.
    _paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 4; k++) {
      _path.reset();
      final amp = (motion.idle + 0.85 * motion.level) *
          (0.9 - k * 0.16) *
          size.height /
          2;
      for (var j = 0; j <= 64; j++) {
        final x = -1 + 2 * j / 64;
        final env = math.pow(math.max(0, 1 - x * x), 1.6).toDouble();
        final y = size.height / 2 +
            amp *
                env *
                math.sin((2.2 + k * 0.9) * x +
                    motion.phase * (1.1 + k * 0.45) +
                    k * 1.7);
        final px = (x + 1) / 2 * size.width;
        j == 0 ? _path.moveTo(px, y) : _path.lineTo(px, y);
      }
      _paint
        ..color = colors[k].withValues(alpha: 0.8)
        ..strokeWidth = 1.5 + 2 * motion.level;
      canvas.drawPath(_path, _paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.clock != clock ||
      old.motion != motion ||
      old.shader != shader ||
      !listEquals(old.colors, colors) ||
      old.dark != dark;
}

/// An iridescent glow that hugs the inside edge of [child] while the
/// assistant is [active]: around the whole screen, a card or an input.
/// It fades in and out, flows along the edge and breathes with [level].
/// It never intercepts input and is invisible to screen readers.
class NeuralEdgeGlow extends StatefulWidget {
  /// Wraps [child].
  const NeuralEdgeGlow({
    super.key,
    required this.child,
    this.active = true,
    this.level = 0,
    this.borderRadius = 32,
    this.width = 28,
    this.colors,
    this.duration = const Duration(milliseconds: 600),
  });

  /// The framed content.
  final Widget child;

  /// Show the glow.
  final bool active;

  /// Voice level `0..1`.
  final double level;

  /// Corner radius of the frame (use the device corner radius around a
  /// full-screen layout).
  final double borderRadius;

  /// Glow depth in logical pixels.
  final double width;

  /// Four flow colors. Defaults to the theme spectrum.
  final List<Color>? colors;

  /// Fade duration.
  final Duration duration;

  @override
  State<NeuralEdgeGlow> createState() => _NeuralEdgeGlowState();
}

/// Live edge-glow values.
class EdgeMotion {
  /// Flow phase.
  double phase = 0;

  /// Smoothed level.
  double level = 0;
}

class _NeuralEdgeGlowState extends State<NeuralEdgeGlow>
    with TickerProviderStateMixin, _ShaderHost {
  @override
  NeuralShader get shaderKind => NeuralShader.edgeGlow;
  final EdgeMotion _m = EdgeMotion();
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.active ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    initShader();
    clock.onTick = (dt) {
      _m.level = _follow(_m.level, unit(widget.level), dt, 8);
      _m.phase += dt * (1 + 1.5 * _m.level);
    };
    _fade.addStatusListener((_) => _sync());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion = reduceMotionOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(NeuralEdgeGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fade.duration = widget.duration;
    if (widget.active != oldWidget.active) {
      if (reduceMotion) {
        _fade.value = widget.active ? 1 : 0;
      } else {
        widget.active ? _fade.forward() : _fade.reverse();
      }
    }
    _sync();
  }

  void _sync() {
    // Tick only while visible.
    final visible = _fade.value > 0 || widget.active;
    clock.setRunning(visible && !reduceMotion);
    if (reduceMotion) {
      _m.level = unit(widget.level);
      clock.advance(0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    disposeShader();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = NeuralPalette.of(context);
    final colors = widget.colors ?? palette.spectrum;
    final four = [for (var i = 0; i < 4; i++) colors[i % colors.length]];
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _EdgePainter(
                    clock: clock,
                    fade: _fade,
                    motion: _m,
                    shader: shader,
                    colors: four,
                    radius:
                        finiteOr(widget.borderRadius, 32).clamp(0.0, 2000.0),
                    width: finiteOr(widget.width, 28).clamp(1.0, 400.0),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.clock,
    required this.fade,
    required this.motion,
    required this.shader,
    required this.colors,
    required this.radius,
    required this.width,
  }) : super(repaint: Listenable.merge([clock, fade]));

  final ValueListenable<double> clock;
  final Animation<double> fade;
  final EdgeMotion motion;
  final ui.FragmentShader? shader;
  final List<Color> colors;
  final double radius;
  final double width;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite || fade.value <= 0) return;
    final active = Curves.easeOut.transform(fade.value);
    final s = shader;
    if (s != null) {
      var i = 0;
      void f(double v) => s.setFloat(i++, v);
      f(size.width);
      f(size.height);
      f(motion.phase);
      f(motion.level);
      f(active);
      f(radius);
      f(width);
      for (final c in colors) {
        f(c.r);
        f(c.g);
        f(c.b);
        f(1);
      }
      _paint
        ..shader = s
        ..color = const Color(0xFF000000);
      canvas.drawRect(Offset.zero & size, _paint);
      _paint.shader = null;
      return;
    }
    final rr = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(width * 0.25),
      Radius.circular(radius),
    );
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.5
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.4)
      ..shader = SweepGradient(
        colors: [...colors, colors.first],
        transform: GradientRotation(motion.phase * 0.4),
      ).createShader(Offset.zero & size)
      ..color = Color.fromRGBO(0, 0, 0, (0.8 * active).clamp(0.0, 1.0));
    canvas.drawRRect(rr, _paint);
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.clock != clock ||
      old.fade != fade ||
      old.motion != motion ||
      old.shader != shader ||
      !listEquals(old.colors, colors) ||
      old.radius != radius ||
      old.width != width;
}

/// Light on the rim of a liquid-glass slab, drawn over a surface of size
/// [Size] with corner [radius]. Used by `NeuralGlassCard` in the liquid
/// design; exposed for custom glass surfaces.
class LiquidGlassRim extends StatefulWidget {
  /// Creates a rim overlay that sizes itself to its parent.
  const LiquidGlassRim({
    super.key,
    this.radius = 24,
    this.emphasis,
    this.dispersion = 1,
    this.animate = true,
  });

  /// Corner radius.
  final double radius;

  /// Hover / focus emphasis `0..1`.
  final Animation<double>? emphasis;

  /// Prismatic strength.
  final double dispersion;

  /// Run the slow sheen.
  final bool animate;

  @override
  State<LiquidGlassRim> createState() => _LiquidGlassRimState();
}

class _LiquidGlassRimState extends State<LiquidGlassRim>
    with SingleTickerProviderStateMixin, _ShaderHost {
  @override
  NeuralShader get shaderKind => NeuralShader.liquidGlass;

  @override
  void initState() {
    super.initState();
    initShader();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion = reduceMotionOf(context);
    clock.setRunning(widget.animate && !reduceMotion);
  }

  @override
  void didUpdateWidget(LiquidGlassRim oldWidget) {
    super.didUpdateWidget(oldWidget);
    clock.setRunning(widget.animate && !reduceMotion);
  }

  @override
  void dispose() {
    disposeShader();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _RimPainter(
          clock: clock,
          emphasis: widget.emphasis ?? kAlwaysDismissedAnimation,
          shader: shader,
          radius: finiteOr(widget.radius, 24).clamp(0.0, 2000.0),
          dark: dark,
          dispersion: finiteOr(widget.dispersion, 1).clamp(0.0, 2.0),
        ),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter({
    required this.clock,
    required this.emphasis,
    required this.shader,
    required this.radius,
    required this.dark,
    required this.dispersion,
  }) : super(repaint: Listenable.merge([clock, emphasis]));

  final ValueListenable<double> clock;
  final Animation<double> emphasis;
  final ui.FragmentShader? shader;
  final double radius;
  final bool dark;
  final double dispersion;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final s = shader;
    if (s != null) {
      var i = 0;
      void f(double v) => s.setFloat(i++, v);
      f(size.width);
      f(size.height);
      f(clock.value);
      f(radius);
      f(dark ? 1 : 0);
      f(dispersion);
      f(emphasis.value);
      f(0.55); // light from the top-left
      f(0.83);
      _paint
        ..shader = s
        ..color = const Color(0xFF000000);
      canvas.drawRect(Offset.zero & size, _paint);
      _paint.shader = null;
      return;
    }
    final rr = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.5), Radius.circular(radius));
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: dark ? 0.4 : 0.9),
          Colors.white.withValues(alpha: 0.05),
          Colors.white.withValues(alpha: dark ? 0.15 : 0.4),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rr, _paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.clock != clock ||
      old.emphasis != emphasis ||
      old.shader != shader ||
      old.radius != radius ||
      old.dark != dark ||
      old.dispersion != dispersion;
}
