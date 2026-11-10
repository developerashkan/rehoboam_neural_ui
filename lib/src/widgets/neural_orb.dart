import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';

/// What an AI assistant is doing, as shown by [NeuralOrb].
enum NeuralOrbState {
  /// Resting: slow breathing.
  idle,

  /// Hearing the user: the surface ripples with the input level.
  listening,

  /// Reasoning: an inner vortex spins and synapse sparks orbit.
  thinking,

  /// Answering: bold, level-driven surface waves.
  speaking,
}

/// A liquid, glowing assistant orb with four states.
///
/// The surface is a closed curve built from a handful of sine harmonics, so
/// it morphs organically; [level] (mic or TTS amplitude, `0..1`) is smoothed
/// internally, so you can feed raw readings straight in. State changes ease
/// over ~400 ms instead of snapping.
///
/// ```dart
/// NeuralOrb(state: NeuralOrbState.listening, level: micLevel, onTap: toggle)
/// ```
class NeuralOrb extends StatefulWidget {
  /// Creates an orb.
  const NeuralOrb({
    super.key,
    this.state = NeuralOrbState.idle,
    this.level = 0,
    this.size = 160,
    this.color,
    this.secondaryColor,
    this.speed = 1,
    this.onTap,
    this.semanticsLabel,
    this.animate = true,
  });

  /// What the assistant is doing.
  final NeuralOrbState state;

  /// Audio level `0..1`; NaN is treated as silence.
  final double level;

  /// Diameter of the orb's box (the glow fills it).
  final double size;

  /// Core color. Defaults to the theme accent (`primary`).
  final Color? color;

  /// Highlight color. Defaults to the theme secondary (`tertiary`).
  final Color? secondaryColor;

  /// Time multiplier.
  final double speed;

  /// Makes the orb a button (e.g. push-to-talk).
  final VoidCallback? onTap;

  /// Accessibility label. Defaults to "AI assistant, `state`".
  final String? semanticsLabel;

  /// Set to `false` for a still frame.
  final bool animate;

  @override
  State<NeuralOrb> createState() => _NeuralOrbState();
}

/// Animated shape parameters (eased toward the state's targets each tick).
class OrbParams {
  /// Surface wobble amplitude (fraction of radius).
  double wobble = 0.02;

  /// Inner vortex strength `0..1`.
  double vortex = 0;

  /// Orbiting spark visibility `0..1`.
  double sparks = 0;

  /// Smoothed level.
  double level = 0;

  /// Glow strength.
  double glow = 0.6;

  /// Targets for [state] at input [level].
  static OrbParams target(NeuralOrbState state, double level) {
    final p = OrbParams()..level = level;
    switch (state) {
      case NeuralOrbState.idle:
        p
          ..wobble = 0.025
          ..vortex = 0.15
          ..sparks = 0
          ..glow = 0.55;
      case NeuralOrbState.listening:
        p
          ..wobble = 0.03 + 0.10 * level
          ..vortex = 0.25
          ..sparks = 0.2
          ..glow = 0.7 + 0.3 * level;
      case NeuralOrbState.thinking:
        p
          ..wobble = 0.045
          ..vortex = 1
          ..sparks = 1
          ..glow = 0.8;
      case NeuralOrbState.speaking:
        p
          ..wobble = 0.04 + 0.16 * level
          ..vortex = 0.4
          ..sparks = 0.35
          ..glow = 0.75 + 0.35 * level;
    }
    return p;
  }

  /// Moves this toward [t] by factor [k] (`1` jumps).
  void easeTo(OrbParams t, double k) {
    wobble += (t.wobble - wobble) * k;
    vortex += (t.vortex - vortex) * k;
    sparks += (t.sparks - sparks) * k;
    level += (t.level - level) * k;
    glow += (t.glow - glow) * k;
  }
}

class _NeuralOrbState extends State<NeuralOrb>
    with SingleTickerProviderStateMixin {
  late final NeuralClock _clock = NeuralClock(this, speed: widget.speed)
    ..onTick = _onTick;
  final OrbParams _params = OrbParams();
  bool _reduce = false;
  bool _seeded = false;

  void _onTick(double dt) {
    // Frame-rate independent easing (~400 ms to settle).
    final k = 1 - math.exp(-dt * 8);
    _params.easeTo(OrbParams.target(widget.state, unit(widget.level)), k);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotionOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(NeuralOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    _clock.speed = widget.speed;
    final running = widget.animate && !_reduce && _clock.speed > 0;
    if (!running || !_seeded) {
      // Still frame (or first frame): show the target state immediately.
      _params.easeTo(OrbParams.target(widget.state, unit(widget.level)), 1);
      _seeded = true;
    }
    _clock.setRunning(running);
    if (!running) _clock.advance(0); // repaint the still frame
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = NeuralPalette.of(
      context,
      accent: widget.color,
      secondary: widget.secondaryColor,
    );
    final size = finiteOr(widget.size, 160).clamp(0.0, double.maxFinite);
    Widget orb = SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: NeuralOrbPainter(
            clock: _clock,
            params: _params,
            state: widget.state,
            palette: palette,
          ),
        ),
      ),
    );
    if (widget.onTap != null) {
      orb = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: widget.onTap, child: orb),
      );
    }
    return Semantics(
      button: widget.onTap != null,
      onTap: widget.onTap,
      label: widget.semanticsLabel ?? 'AI assistant, ${widget.state.name}',
      child: orb,
    );
  }
}

/// Paints [NeuralOrb].
class NeuralOrbPainter extends CustomPainter {
  /// Creates the painter.
  NeuralOrbPainter({
    required this.clock,
    required this.params,
    required this.state,
    required this.palette,
  }) : super(repaint: clock);

  /// Elapsed seconds.
  final ValueListenable<double> clock;

  /// Live shape parameters.
  final OrbParams params;

  /// Current state (for change detection).
  final NeuralOrbState state;

  /// Colors.
  final NeuralPalette palette;

  static const int _samples = 96;
  final Path _path = Path();
  final Paint _paint = Paint();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  ui.Shader? _glow;
  ui.Shader? _body;
  ui.Shader? _spec;

  void _ensureShaders() {
    final a = palette.accent;
    final b = palette.secondary;
    final dark = palette.isDark;
    _glow ??= ui.Gradient.radial(Offset.zero, 1, [
      a.withValues(alpha: 0.55),
      a.withValues(alpha: 0.18),
      a.withValues(alpha: 0),
    ], [
      0,
      0.45,
      1
    ]);
    _body ??= ui.Gradient.radial(
      const Offset(-0.35, -0.4),
      1.5,
      [
        Color.lerp(b, Colors.white, dark ? 0.35 : 0.2)!,
        b,
        a,
        Color.lerp(a, Colors.black, dark ? 0.55 : 0.35)!,
      ],
      [0, 0.25, 0.6, 1],
    );
    _spec ??= ui.Gradient.radial(Offset.zero, 1, [
      Colors.white.withValues(alpha: 0.75),
      Colors.white.withValues(alpha: 0),
    ]);
  }

  /// The surface radius (unit circle = 1) at [theta] and time [s].
  static double surface(double theta, double s, double wobble, double level) {
    final w = wobble;
    return 1 +
        w * math.sin(3 * theta + s * 1.3) +
        w * 0.7 * math.sin(5 * theta - s * 1.9 + 1.1) +
        w * (0.4 + level) * 0.6 * math.sin(7 * theta + s * 3.1 + 2.3) +
        0.012 * math.sin(s * 1.6); // breathing
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    _ensureShaders();
    final s = clock.value;
    final p = params;
    final center = size.center(Offset.zero);
    final full = size.shortestSide / 2;
    final r = full * 0.58;
    final glowK = (p.glow * palette.glowIntensity).clamp(0.0, 2.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);

    // 1. Halo.
    if (glowK > 0) {
      _paint
        ..shader = _glow
        ..color = Color.fromRGBO(0, 0, 0, (glowK * 0.8).clamp(0.0, 1.0));
      canvas.save();
      canvas.scale(full * (0.92 + 0.08 * p.level));
      canvas.drawCircle(Offset.zero, 1, _paint);
      canvas.restore();
    }

    // 2. Liquid body (unit-space path, scaled).
    _path.reset();
    for (var i = 0; i <= _samples; i++) {
      final th = i * 2 * math.pi / _samples;
      final rr = surface(th, s, p.wobble, p.level);
      final x = math.cos(th) * rr;
      final y = math.sin(th) * rr;
      if (i == 0) {
        _path.moveTo(x, y);
      } else {
        _path.lineTo(x, y);
      }
    }
    _path.close();
    canvas.save();
    canvas.scale(r);
    _paint
      ..shader = _body
      ..color = const Color(0xFF000000);
    canvas.drawPath(_path, _paint);

    // 3. Inner vortex: three counter-rotating arcs clipped to the body.
    if (p.vortex > 0.01) {
      canvas.save();
      canvas.clipPath(_path);
      final spin = s * (0.6 + 2.4 * p.vortex);
      for (var k = 0; k < 3; k++) {
        final rad = 0.35 + 0.22 * k;
        _stroke
          ..strokeWidth = 0.05 + 0.03 * (2 - k)
          ..color = Colors.white.withValues(
            alpha: (0.10 + 0.16 * p.vortex) * (1 - k * 0.25),
          );
        final dirSign = k.isEven ? 1 : -1;
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: rad),
          spin * dirSign + k * 2.1,
          math.pi * (0.5 + 0.6 * p.vortex),
          false,
          _stroke,
        );
      }
      canvas.restore();
    }

    // 4. Specular highlight.
    _paint
      ..shader = _spec
      ..color = const Color(0xFF000000);
    canvas.save();
    canvas.translate(-0.32, -0.38);
    canvas.scale(0.42, 0.3);
    canvas.drawCircle(Offset.zero, 1, _paint);
    canvas.restore();

    // 5. Rim light.
    _stroke
      ..strokeWidth = 0.025
      ..color = Color.lerp(palette.secondary, Colors.white, 0.5)!
          .withValues(alpha: 0.55);
    canvas.drawPath(_path, _stroke);
    canvas.restore(); // unit scale

    // 6. Synapse sparks orbiting (thinking).
    if (p.sparks > 0.01) {
      _paint
        ..shader = null
        ..color = Color.lerp(palette.secondary, Colors.white, 0.4)!
            .withValues(alpha: 0.9 * p.sparks);
      for (var i = 0; i < 9; i++) {
        final phase = s * (1.1 + (i % 3) * 0.35) + i * 0.7;
        final orbit = r * (1.18 + 0.12 * math.sin(i * 1.3 + s * 0.5));
        final tilt = 0.45 + 0.25 * (i % 3);
        final pos = Offset(
          math.cos(phase) * orbit,
          math.sin(phase) * orbit * tilt,
        );
        final dot = full * (0.012 + 0.012 * (0.5 + 0.5 * math.sin(s * 3 + i)));
        canvas.drawCircle(pos, dot, _paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(NeuralOrbPainter old) =>
      old.clock != clock ||
      old.params != params ||
      old.state != state ||
      old.palette != palette;
}
