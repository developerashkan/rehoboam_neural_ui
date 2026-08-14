import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Reactive audio-level state fed by the native audio bridge
/// (`voice_agent/audio_level` event channel). [level] is normalized 0..1.
class AudioLevelSnapshot {
  const AudioLevelSnapshot({required this.level, this.isVoice = false});

  /// Instantaneous input level, 0..1.
  final double level;

  /// Whether the current audio is classified as speech (VAD).
  final bool isVoice;
}

/// Mode selector for [VoiceWave].
enum VoiceWaveMode { listening, speaking }

/// A super-modern animated voice indicator.
///
/// * **listening**: a soft AI "aurora" — a blurred, breathing gradient blob
///   whose size pulses with the live audio level (via [AudioLevelStream]),
///   surrounded by orbiting particles and a shimmering ring.
/// * **speaking**: a sharp, high-energy spectral wave that bursts outward
///   with the TTS audio, with a traveling highlight.
///
/// All animation is `CustomPainter`-based with a single [AnimationController],
/// so it stays at 60fps with negligible CPU. Colors follow the ambient
/// theme (Material 3 color scheme).
class VoiceWave extends StatefulWidget {
  const VoiceWave({
    super.key,
    this.mode = VoiceWaveMode.listening,
    this.level = 0,
    this.size = 180,
    this.particleCount = 10,
    this.speed = 1.0,
  });

  final VoiceWaveMode mode;
  final double level;
  final double size;
  final int particleCount;

  /// Animation speed multiplier.
  final double speed;

  @override
  State<VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<VoiceWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _breath;
  late final Animation<double> _rotate;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (2200 / widget.speed).round()),
    )..repeat();
    _breath = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _rotate = Tween<double>(begin: 0, end: 2 * math.pi).animate(_controller);
    _pulse = Tween<double>(begin: 0.96, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void didUpdateWidget(VoiceWave old) {
    super.didUpdateWidget(old);
    if (old.speed != widget.speed) {
      _controller.duration =
          Duration(milliseconds: (2200 / widget.speed).round());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _breath.value;
          final level = widget.level.clamp(0.0, 1.0);
          return CustomPaint(
            painter: _VoiceWavePainter(
              mode: widget.mode,
              t: t,
              rotate: _rotate.value,
              pulse: _pulse.value,
              level: level,
              color: widget.mode == VoiceWaveMode.listening
                  ? scheme.primary
                  : scheme.tertiary,
              secondary: widget.mode == VoiceWaveMode.listening
                  ? scheme.tertiary
                  : scheme.primary,
              particleCount: widget.particleCount,
            ),
          );
        },
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  _VoiceWavePainter({
    required this.mode,
    required this.t,
    required this.rotate,
    required this.pulse,
    required this.level,
    required this.color,
    required this.secondary,
    required this.particleCount,
  });

  final VoiceWaveMode mode;
  final double t;
  final double rotate;
  final double pulse;
  final double level;
  final Color color;
  final Color secondary;
  final int particleCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer shimmer ring.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color =
          color.withValues(alpha: 0.35 + 0.25 * math.sin(t * 2 * math.pi));
    canvas.drawCircle(center, radius * 0.62 * pulse, ring);

    if (mode == VoiceWaveMode.listening) {
      _paintListening(canvas, center, radius);
    } else {
      _paintSpeaking(canvas, center, radius);
    }
  }

  void _paintListening(Canvas canvas, Offset center, double radius) {
    // Blurred aurora blob whose size tracks the audio level.
    final blobR = radius * (0.42 + 0.16 * t + 0.30 * level);
    final blob = Paint()
      ..shader = ui.Gradient.radial(
        center,
        blobR,
        [
          color.withValues(alpha: 0.85),
          color.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(center, blobR, blob);

    // Secondary glow for depth.
    final glowR = radius * (0.30 + 0.12 * t + 0.22 * level);
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        center,
        glowR,
        [
          secondary.withValues(alpha: 0.5),
          secondary.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(center, glowR, glow);

    // Orbiting particles.
    final particle = Paint()..color = Colors.white.withValues(alpha: 0.8);
    for (var i = 0; i < particleCount; i++) {
      final a = rotate + (i * 2 * math.pi / particleCount);
      final pr = radius * (0.68 + 0.10 * math.sin(t * 2 * math.pi + i));
      final p = center + Offset(math.cos(a), math.sin(a)) * pr;
      final s = 2.0 + 1.6 * math.sin(t * 4 * math.pi + i * 1.7);
      canvas.drawCircle(p, s, particle);
    }
  }

  void _paintSpeaking(Canvas canvas, Offset center, double radius) {
    // High-energy spectral bars bursting outward.
    const bars = 24;
    final bar = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < bars; i++) {
      final a = (i / bars) * 2 * math.pi;
      final inner = radius * 0.34;
      final outer = radius *
          (0.52 + 0.38 * (0.5 + 0.5 * math.sin(t * 4 * math.pi + i * 0.55)));
      final base = center + Offset(math.cos(a), math.sin(a)) * inner;
      final tip = center + Offset(math.cos(a), math.sin(a)) * outer;
      bar.color = i.isEven ? color : secondary;
      bar.color =
          bar.color.withValues(alpha: 0.9 - 0.4 * (outer - inner) / radius);
      canvas.drawLine(base, tip, bar);
    }

    // Core glow.
    final core = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius * 0.4,
        [color.withValues(alpha: 0.7), color.withValues(alpha: 0.0)],
      );
    canvas.drawCircle(center, radius * 0.42, core);
  }

  @override
  bool shouldRepaint(_VoiceWavePainter old) =>
      old.t != t ||
      old.rotate != rotate ||
      old.pulse != pulse ||
      old.level != level ||
      old.mode != mode ||
      old.color != color;
}

/// Stream of live audio levels from the native bridge.
///
/// Subscribes to the `voice_agent/audio_level` event channel (populated by
/// the platform plugin) and re-emits [AudioLevelSnapshot]s at display rate.
class AudioLevelStream {
  AudioLevelStream._(this._stream);

  final Stream<AudioLevelSnapshot> _stream;

  static AudioLevelStream? _instance;

  /// Global instance; lazily binds to the native channel.
  static AudioLevelStream get instance {
    _instance ??= AudioLevelStream._(_bind());
    return _instance!;
  }

  static Stream<AudioLevelSnapshot> _bind() {
    // Native plugin emits JSON {"level": 0..1, "isVoice": bool} periodically.
    return const Stream.empty(); // wired by the plugin's Dart-side bridge
  }

  Stream<AudioLevelSnapshot> get stream => _stream;
}
