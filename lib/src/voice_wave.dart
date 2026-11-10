import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/neural_clock.dart';
import 'core/neural_theme.dart';

/// One audio-level reading. [level] is normalized `0..1`.
class AudioLevelSnapshot {
  /// Creates a reading.
  const AudioLevelSnapshot({required this.level, this.isVoice = false});

  /// Instantaneous input level, `0..1`.
  final double level;

  /// Whether the current audio is classified as speech (VAD).
  final bool isVoice;
}

/// Mode selector for [VoiceWave].
enum VoiceWaveMode {
  /// Soft breathing aurora that grows with the input level.
  listening,

  /// Sharp spectral bars bursting outward.
  speaking,
}

/// A super-modern animated voice indicator.
///
/// * **listening**: a soft AI "aurora": a breathing gradient blob whose size
///   pulses with [level], surrounded by orbiting particles and a ring.
/// * **speaking**: a sharp, high-energy spectral burst.
///
/// One ticker drives a `CustomPainter` directly (no per-frame rebuilds).
/// Colors follow the ambient [ColorScheme]; `MediaQuery.disableAnimations`
/// shows a still frame.
class VoiceWave extends StatefulWidget {
  /// Creates a voice indicator.
  const VoiceWave({
    super.key,
    this.mode = VoiceWaveMode.listening,
    this.level = 0,
    this.size = 180,
    this.particleCount = 10,
    this.speed = 1.0,
    this.color,
    this.secondaryColor,
    this.particleColor,
    this.semanticsLabel,
  });

  /// Listening or speaking.
  final VoiceWaveMode mode;

  /// Input level, `0..1`.
  final double level;

  /// Side of the square widget.
  final double size;

  /// Orbiting particles in listening mode.
  final int particleCount;

  /// Animation speed multiplier (`0` freezes).
  final double speed;

  /// Main color. Defaults to `primary` (listening) / `tertiary` (speaking).
  final Color? color;

  /// Second color. Defaults to the other of `primary` / `tertiary`.
  final Color? secondaryColor;

  /// Orbiting particle color. Defaults to `onSurface`.
  final Color? particleColor;

  /// Accessibility label. Defaults to "Listening" / "Speaking".
  final String? semanticsLabel;

  @override
  State<VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<VoiceWave>
    with SingleTickerProviderStateMixin {
  late final NeuralClock _clock = NeuralClock(this, speed: widget.speed);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(VoiceWave old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    _clock.speed = widget.speed;
    _clock.setRunning(!reduceMotionOf(context) && _clock.speed > 0);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = NeuralPalette.of(context);
    final listening = widget.mode == VoiceWaveMode.listening;
    // Liquid design: iridescent stops instead of primary / tertiary.
    final a = palette.isLiquid
        ? palette.strokeAt(listening ? 0.7 : 0.3)
        : (listening ? scheme.primary : scheme.tertiary);
    final b = palette.isLiquid
        ? palette.strokeAt(listening ? 0.25 : 0.85)
        : (listening ? scheme.tertiary : scheme.primary);
    final size = finiteOr(widget.size, 180).clamp(0.0, double.maxFinite);
    return Semantics(
      label: widget.semanticsLabel ?? (listening ? 'Listening' : 'Speaking'),
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: VoiceWavePainter(
              clock: _clock,
              mode: widget.mode,
              level: unit(widget.level),
              color: widget.color ?? a,
              secondary: widget.secondaryColor ?? b,
              particleColor: widget.particleColor ?? scheme.onSurface,
              particleCount: math.max(0, widget.particleCount),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints [VoiceWave]. Public for testing and for custom compositions.
class VoiceWavePainter extends CustomPainter {
  /// Creates the painter. [clock] is elapsed seconds.
  VoiceWavePainter({
    required this.clock,
    required this.mode,
    required this.level,
    required this.color,
    required this.secondary,
    required this.particleColor,
    required this.particleCount,
  }) : super(repaint: clock);

  /// Elapsed animation seconds.
  final ValueListenable<double> clock;

  /// Listening or speaking.
  final VoiceWaveMode mode;

  /// Level `0..1`.
  final double level;

  /// Main color.
  final Color color;

  /// Second color.
  final Color secondary;

  /// Particle color.
  final Color particleColor;

  /// Orbiting particles.
  final int particleCount;

  static const double _period = 2.2;

  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  final Paint _fill = Paint();
  final Paint _bar = Paint()..strokeCap = StrokeCap.round;
  ui.Shader? _blobShader;
  ui.Shader? _glowShader;

  /// Breathing phase in `[0, 1]`, smooth at every loop point.
  static double breathAt(double seconds) =>
      0.5 - 0.5 * math.cos(2 * math.pi * seconds / _period);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final s = clock.value;
    final phase = 2 * math.pi * s / _period; // radians, never wraps
    final t = breathAt(s);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final pulse = 1.01 + 0.05 * math.sin(phase);

    _ring.color =
        color.withValues(alpha: (0.35 + 0.25 * math.sin(phase)) * color.a);
    canvas.drawCircle(center, radius * 0.62 * pulse, _ring);

    if (mode == VoiceWaveMode.listening) {
      _paintListening(canvas, center, radius, t, phase);
    } else {
      _paintSpeaking(canvas, center, radius, phase);
    }
  }

  // Radial gradients are built once at unit radius and scaled by the canvas,
  // so the per-frame size changes allocate nothing.
  void _unitBlob(Canvas canvas, Offset c, double r, ui.Shader shader) {
    if (r <= 0) return;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(r);
    _fill
      ..shader = shader
      ..color = const Color(0xFF000000); // opaque: alpha would dim the shader
    canvas.drawCircle(Offset.zero, 1, _fill);
    canvas.restore();
  }

  void _paintListening(
    Canvas canvas,
    Offset center,
    double radius,
    double t,
    double phase,
  ) {
    _blobShader ??= ui.Gradient.radial(Offset.zero, 1, [
      color.withValues(alpha: 0.85 * color.a),
      color.withValues(alpha: 0),
    ]);
    _glowShader ??= ui.Gradient.radial(Offset.zero, 1, [
      secondary.withValues(alpha: 0.5 * secondary.a),
      secondary.withValues(alpha: 0),
    ]);
    _unitBlob(canvas, center, radius * (0.42 + 0.16 * t + 0.30 * level),
        _blobShader!);
    _unitBlob(canvas, center, radius * (0.30 + 0.12 * t + 0.22 * level),
        _glowShader!);

    if (particleCount == 0) return;
    _fill
      ..shader = null
      ..color = particleColor.withValues(alpha: 0.8 * particleColor.a);
    for (var i = 0; i < particleCount; i++) {
      final a = phase + (i * 2 * math.pi / particleCount);
      final pr = radius * (0.68 + 0.10 * math.sin(phase + i));
      final p = center + Offset(math.cos(a), math.sin(a)) * pr;
      final dot = (2.0 + 1.6 * math.sin(phase * 2 + i * 1.7)) *
          (radius / 90).clamp(0.5, 3.0);
      canvas.drawCircle(p, dot, _fill);
    }
  }

  void _paintSpeaking(
      Canvas canvas, Offset center, double radius, double phase) {
    const bars = 24;
    _bar.strokeWidth = math.max(1.5, radius * 0.045);
    for (var i = 0; i < bars; i++) {
      final a = (i / bars) * 2 * math.pi;
      final inner = radius * 0.34;
      final wave = 0.5 + 0.5 * math.sin(phase * 2 + i * 0.55);
      final outer = radius * (0.50 + (0.22 + 0.24 * level) * wave);
      final dir = Offset(math.cos(a), math.sin(a));
      final base = i.isEven ? color : secondary;
      _bar.color = base.withValues(
        alpha: ((0.9 - 0.4 * (outer - inner) / radius) * base.a).clamp(0, 1),
      );
      canvas.drawLine(center + dir * inner, center + dir * outer, _bar);
    }
    _blobShader ??= ui.Gradient.radial(Offset.zero, 1, [
      color.withValues(alpha: 0.7 * color.a),
      color.withValues(alpha: 0),
    ]);
    _unitBlob(canvas, center, radius * 0.42, _blobShader!);
  }

  @override
  bool shouldRepaint(VoiceWavePainter old) =>
      old.clock != clock ||
      old.level != level ||
      old.mode != mode ||
      old.color != color ||
      old.secondary != secondary ||
      old.particleColor != particleColor ||
      old.particleCount != particleCount;
}

/// A broadcast hub for live audio levels.
///
/// The package does not capture audio itself (that needs a platform
/// plugin such as `record` or `flutter_sound`). Feed readings in with
/// [add] or [addLevel] from whatever recorder you use, and listen to
/// [stream] to drive [VoiceWave], `NeuralOrb` or [AiThinkingAnimation]:
///
/// ```dart
/// recorder.onAmplitude.listen((a) => AudioLevelStream.instance.addLevel(a));
/// ```
class AudioLevelStream {
  AudioLevelStream._();

  static final AudioLevelStream _instance = AudioLevelStream._();

  /// The shared hub.
  static AudioLevelStream get instance => _instance;

  final StreamController<AudioLevelSnapshot> _controller =
      StreamController<AudioLevelSnapshot>.broadcast();

  AudioLevelSnapshot _latest = const AudioLevelSnapshot(level: 0);

  /// Live readings (broadcast).
  Stream<AudioLevelSnapshot> get stream => _controller.stream;

  /// The most recent reading.
  AudioLevelSnapshot get latest => _latest;

  /// Publishes a reading; the level is clamped to `0..1` (NaN becomes 0).
  void add(AudioLevelSnapshot snapshot) {
    _latest = AudioLevelSnapshot(
      level: unit(snapshot.level),
      isVoice: snapshot.isVoice,
    );
    _controller.add(_latest);
  }

  /// Publishes a bare level.
  void addLevel(double level, {bool isVoice = false}) =>
      add(AudioLevelSnapshot(level: level, isVoice: isVoice));
}
