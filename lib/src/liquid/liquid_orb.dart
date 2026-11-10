import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../widgets/neural_orb.dart' show NeuralOrbState, OrbParams;
import 'neural_shaders.dart';

/// The two fluids and rim light of a [NeuralLiquidOrb].
@immutable
class LiquidPalette {
  /// Creates a palette.
  const LiquidPalette({
    required this.top,
    required this.bottom,
    this.rim = const Color(0xFFFFFFFF),
    this.dispersion = 1,
  });

  /// Derives a palette from a color scheme's primary color.
  factory LiquidPalette.fromScheme(ColorScheme scheme) => LiquidPalette(
        top: Color.lerp(scheme.primary, const Color(0xFF000000), 0.72)!,
        bottom: Color.lerp(scheme.primary, const Color(0xFFFFFFFF), 0.55)!,
      );

  /// Graphite over mercury: the pure default.
  static const graphite =
      LiquidPalette(top: Color(0xFF2C2E34), bottom: Color(0xFFC6CAD1));

  /// Indigo night over ice blue.
  static const aurora =
      LiquidPalette(top: Color(0xFF1A1442), bottom: Color(0xFF8FD8FF));

  /// Smoked garnet over amber.
  static const ember =
      LiquidPalette(top: Color(0xFF2B0F0C), bottom: Color(0xFFFFB774));

  /// Abyss over lagoon.
  static const ocean =
      LiquidPalette(top: Color(0xFF062A39), bottom: Color(0xFF74E6D9));

  /// Plum over orchid.
  static const orchid =
      LiquidPalette(top: Color(0xFF27103B), bottom: Color(0xFFE5ACFF));

  /// Upper fluid.
  final Color top;

  /// Lower, light-carrying fluid.
  final Color bottom;

  /// Rim light tint.
  final Color rim;

  /// Prismatic strength (`0` = no rainbow, `1` = default, up to `1.5`).
  final double dispersion;

  @override
  bool operator ==(Object other) =>
      other is LiquidPalette &&
      other.top == top &&
      other.bottom == bottom &&
      other.rim == rim &&
      other.dispersion == dispersion;

  @override
  int get hashCode => Object.hash(top, bottom, rim, dispersion);
}

/// A liquid-glass assistant orb: a glass sphere holding two fluids whose
/// flowing interface splits light into a prismatic band.
///
/// It reacts to [state] (idle, listening, thinking, speaking) and to
/// [level] (mic or TTS amplitude). Set [tile] to present it as an app-icon
/// style glass tile. Rendered by a GPU fragment shader on every platform,
/// with a gradient fallback until (or if never) the shader loads.
///
/// [NeuralOrb] renders this automatically in the liquid design.
class NeuralLiquidOrb extends StatefulWidget {
  /// Creates a liquid orb.
  const NeuralLiquidOrb({
    super.key,
    this.state = NeuralOrbState.idle,
    this.level = 0,
    this.size = 160,
    this.palette = LiquidPalette.graphite,
    this.tile = false,
    this.speed = 1,
    this.onTap,
    this.semanticsLabel,
    this.animate = true,
  });

  /// What the assistant is doing.
  final NeuralOrbState state;

  /// Audio level `0..1`, smoothed internally.
  final double level;

  /// Side of the widget.
  final double size;

  /// Fluids and rim.
  final LiquidPalette palette;

  /// Present inside a rounded glass tile (app-icon style).
  final bool tile;

  /// Time multiplier.
  final double speed;

  /// Makes the orb a button.
  final VoidCallback? onTap;

  /// Accessibility label. Defaults to "AI assistant, `state`".
  final String? semanticsLabel;

  /// Set to `false` for a still frame.
  final bool animate;

  @override
  State<NeuralLiquidOrb> createState() => _NeuralLiquidOrbState();
}

/// Live values the orb shader reads each frame.
class LiquidOrbMotion {
  /// Flow phase (seconds, state-scaled).
  double phase = 0;

  /// Accumulated swirl angle.
  double angle = 0;

  /// Shape parameters.
  final OrbParams params = OrbParams();
}

class _NeuralLiquidOrbState extends State<NeuralLiquidOrb>
    with SingleTickerProviderStateMixin {
  late final NeuralClock _clock = NeuralClock(this, speed: widget.speed)
    ..onTick = _onTick;
  final LiquidOrbMotion _motion = LiquidOrbMotion();
  ui.FragmentShader? _shader;
  bool _reduce = false;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _attachShader(NeuralShaders.cached(NeuralShader.liquidOrb));
    if (_shader == null) {
      NeuralShaders.load(NeuralShader.liquidOrb).then((p) {
        if (mounted && p != null) setState(() => _attachShader(p));
      });
    }
  }

  void _attachShader(ui.FragmentProgram? p) {
    if (p == null || _shader != null) return;
    _shader = p.fragmentShader();
  }

  void _onTick(double dt) {
    final p = _motion.params;
    final k = 1 - math.exp(-dt * 6);
    p.easeTo(OrbParams.target(widget.state, unit(widget.level)), k);
    _motion.phase += dt * (0.55 + 1.3 * p.vortex + 1.4 * p.level);
    // Slosh (tilt back and forth) rather than spin: a fluid keeps level.
    _motion.angle = p.vortex * 0.5 * math.sin(_motion.phase * 0.45);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotionOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(NeuralLiquidOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    _clock.speed = widget.speed;
    final running = widget.animate && !_reduce && _clock.speed > 0;
    if (!running || !_seeded) {
      _motion.params
          .easeTo(OrbParams.target(widget.state, unit(widget.level)), 1);
      if (!_seeded) _motion.phase = 1.3; // a pleasing first frame
      _seeded = true;
    }
    _clock.setRunning(running);
    if (!running) _clock.advance(0);
  }

  @override
  void dispose() {
    _clock.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = finiteOr(widget.size, 160).clamp(0.0, double.maxFinite);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final painter = LiquidOrbPainter(
      clock: _clock,
      motion: _motion,
      palette: widget.palette,
      shader: _shader,
      state: widget.state,
      scale: widget.tile ? 0.72 : 0.94,
    );
    Widget orb = RepaintBoundary(child: CustomPaint(painter: painter));
    if (widget.tile) {
      orb = Material(
        color: dark ? const Color(0xFF1D1F24) : const Color(0xFFFCFCFD),
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.28),
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(size * 0.46),
          side: BorderSide(
            color: (dark ? Colors.white : Colors.black)
                .withValues(alpha: dark ? 0.08 : 0.05),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: orb,
      );
    }
    orb = SizedBox.square(dimension: size, child: orb);
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

/// Paints [NeuralLiquidOrb] with the shader, or a gradient fallback.
class LiquidOrbPainter extends CustomPainter {
  /// Creates the painter.
  LiquidOrbPainter({
    required this.clock,
    required this.motion,
    required this.palette,
    required this.shader,
    required this.state,
    required this.scale,
  }) : super(repaint: clock);

  /// Frame clock.
  final ValueListenable<double> clock;

  /// Live motion values.
  final LiquidOrbMotion motion;

  /// Fluids.
  final LiquidPalette palette;

  /// Compiled shader, or `null` for the fallback.
  final ui.FragmentShader? shader;

  /// State (change detection).
  final NeuralOrbState state;

  /// Orb radius relative to the half size.
  final double scale;

  final Paint _paint = Paint();
  final Path _wave = Path();

  /// Whether the shader path is used.
  bool get usesShader => shader != null;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final p = motion.params;
    final amp = 0.2 + p.wobble * 2.4;
    final disp = (palette.dispersion * (0.75 + 0.5 * p.sparks + 0.35 * p.level))
        .clamp(0.0, 1.6);
    final glow = 0.3 + 0.45 * p.glow;
    final r = size.shortestSide / 2 * scale;
    final c = size.center(Offset.zero);

    // Contact shadow under the ball.
    _paint
      ..shader = null
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12);
    canvas.drawOval(
      Rect.fromCenter(
          center: c + Offset(0, r * 0.9), width: r * 1.5, height: r * 0.28),
      _paint,
    );
    _paint.maskFilter = null;

    final s = shader;
    if (s != null) {
      var i = 0;
      void f(double v) => s.setFloat(i++, v);
      void col(Color v) {
        f(v.r);
        f(v.g);
        f(v.b);
        f(v.a);
      }

      f(size.width);
      f(size.height);
      f(motion.phase);
      f(motion.angle);
      f(p.level);
      f(amp);
      f(disp);
      f(glow);
      col(palette.top);
      col(palette.bottom);
      col(palette.rim);
      f(scale);
      _paint
        ..shader = s
        ..color = const Color(0xFF000000);
      canvas.drawRect(Offset.zero & size, _paint);
      _paint.shader = null;
      return;
    }
    _paintFallback(canvas, c, r, amp, disp);
  }

  void _paintFallback(
      Canvas canvas, Offset c, double r, double amp, double disp) {
    final t = motion.phase;
    final circle = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    _paint
      ..shader = ui.Gradient.linear(circle.topCenter, circle.bottomCenter, [
        Color.lerp(palette.top, Colors.black, 0.3)!,
        palette.top,
      ])
      ..color = const Color(0xFF000000);
    canvas.drawRect(circle, _paint);
    _wave.reset();
    const n = 48;
    double yAt(double x) =>
        amp *
            (0.62 * math.sin(1.7 * x + t * 0.9) +
                0.28 * math.sin(3.3 * x - t * 1.35 + 1.3)) -
        0.05;
    for (var k = 0; k <= n; k++) {
      final x = -1.2 + 2.4 * k / n;
      final pt = Offset(c.dx + x * r, c.dy + yAt(x) * r);
      k == 0 ? _wave.moveTo(pt.dx, pt.dy) : _wave.lineTo(pt.dx, pt.dy);
    }
    final line = Path.from(_wave);
    _wave
      ..lineTo(c.dx + 1.2 * r, c.dy + r * 1.2)
      ..lineTo(c.dx - 1.2 * r, c.dy + r * 1.2)
      ..close();
    _paint.shader = ui.Gradient.linear(circle.center, circle.bottomCenter, [
      Color.lerp(palette.bottom, Colors.black, 0.25)!,
      Color.lerp(palette.bottom, Colors.white, 0.35)!,
    ]);
    canvas.drawPath(_wave, _paint);
    _paint
      ..shader =
          ui.Gradient.linear(circle.centerLeft, circle.centerRight, const [
        Color(0x00FF8A5B),
        Color(0xCCFF8A5B),
        Color(0xCC8D6BFF),
        Color(0x0039B8FF),
      ], const [
        0,
        0.35,
        0.65,
        1
      ])
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.05 * (0.5 + disp)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.02);
    canvas.drawPath(line, _paint);
    _paint
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..shader = ui.Gradient.radial(c, r, [
        Colors.transparent,
        Colors.transparent,
        Colors.white.withValues(alpha: 0.35),
      ], [
        0,
        0.8,
        1
      ]);
    canvas.drawRect(circle, _paint);
    _paint.shader = null;
    canvas.restore();
  }

  @override
  bool shouldRepaint(LiquidOrbPainter old) =>
      old.clock != clock ||
      old.motion != motion ||
      old.palette != palette ||
      old.shader != shader ||
      old.state != state ||
      old.scale != scale;
}
