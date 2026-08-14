import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:dot_globe/dot_globe.dart';

/// The visual state of the HUD.
enum HudMode {
  ring,
  earth,
}

/// A high-fidelity "Rehoboam" (Westworld style) data-ring and 3D globe.
class AiThinkingAnimation extends StatefulWidget {
  const AiThinkingAnimation({
    super.key,
    this.level = 0,
    this.mode = AiFaceMode.listening,
    this.hudMode = HudMode.ring,
    this.size = 320,
    this.speed = 1.0,
    this.centerLabel,
    this.topLabel,
    this.bottomLabel,
    this.targetLat,
    this.targetLon,
    this.geoPoints,
    this.dotGlobeController,
    this.dotGlobeStyle = const DotGlobeStyle(
      dotColor: Colors.white,
      sphereColor: Colors.transparent,
    ),
  });

  final double level;
  final AiFaceMode mode;
  final HudMode hudMode;
  final double size;
  final double speed;
  final String? centerLabel;
  final String? topLabel;
  final String? bottomLabel;
  final double? targetLat;
  final double? targetLon;
  final List<Map<String, double>>? geoPoints;
  final DotGlobeController? dotGlobeController;
  final DotGlobeStyle dotGlobeStyle;

  @override
  State<AiThinkingAnimation> createState() => _AiThinkingAnimationState();
}

enum AiFaceMode { listening, speaking }

class _AiThinkingAnimationState extends State<AiThinkingAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _transitionController;
  late final Animation<double> _transitionAnim;

  HudMode _lastMode = HudMode.ring;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();

    _transitionController = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 2200), // Slightly slower for "epic" feel
    );

    _transitionAnim = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeInOutQuart,
    );
  }

  @override
  void didUpdateWidget(AiThinkingAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hudMode != _lastMode) {
      if (widget.hudMode == HudMode.earth) {
        _transitionController.forward();
        _animateToTarget();
      } else {
        _transitionController.reverse();
      }
      _lastMode = widget.hudMode;
    } else if (widget.hudMode == HudMode.earth &&
        (widget.targetLat != oldWidget.targetLat ||
            widget.targetLon != oldWidget.targetLon)) {
      _animateToTarget();
    }
  }

  void _animateToTarget() {
    if (widget.targetLat != null && widget.targetLon != null) {
      widget.dotGlobeController?.animateTo(
        latitude: widget.targetLat!,
        longitude: widget.targetLon!,
        scale: 1.8, // Automatic zoom on city
        duration: const Duration(milliseconds: 1800),
        curve: Curves.easeOutQuart,
      );
    }
  }

  List<DotGlobeMarker> _buildMarkers() {
    final markers = <DotGlobeMarker>[];

    // 1. Single target city marker
    if (widget.targetLat != null && widget.targetLon != null) {
      markers.add(
        DotGlobeMarker(
          latitude: widget.targetLat!,
          longitude: widget.targetLon!,
          child: const _MarkerPulse(magnitude: 6.0, isSignificant: true),
        ),
      );
    }

    // 2. Multi-point seismic markers
    if (widget.geoPoints != null) {
      // Find max magnitude for scaling
      double maxMag = 1.0;
      for (final p in widget.geoPoints!) {
        final m = p['mag'] ?? 1.0;
        if (m > maxMag) maxMag = m;
      }

      for (final point in widget.geoPoints!) {
        final lat = point['lat'];
        final lon = point['lon'];
        final mag = point['mag'] ?? 1.0;

        // Skip if this is the same as target city to avoid overlap
        if (lat == widget.targetLat && lon == widget.targetLon) continue;

        if (lat != null && lon != null) {
          markers.add(
            DotGlobeMarker(
              latitude: lat,
              longitude: lon,
              child: _MarkerPulse(
                magnitude: mag,
                isSignificant: mag >= maxMag && mag > 4.0,
              ),
            ),
          );
        }
      }
    }
    return markers;
  }

  @override
  void dispose() {
    _controller.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _transitionAnim]),
      builder: (context, _) {
        return SizedBox.square(
          dimension: widget.size,
          child: Stack(
            children: [
              if (_transitionAnim.value > 0.01)
                Transform.scale(
                  scale: 0.9 + (0.1 * _transitionAnim.value),
                  child: Opacity(
                    opacity: _transitionAnim.value,
                    child: Center(
                      child: SizedBox.square(
                        dimension: widget.size * 0.7,
                        child: DotGlobe(
                          controller: widget.dotGlobeController,
                          style: widget.dotGlobeStyle,
                          // Use the target coordinates for initial view
                          initialLatitude: widget.targetLat ?? 0,
                          initialLongitude: widget.targetLon ?? 0,
                          markers: _buildMarkers(),
                        ),
                      ),
                    ),
                  ),
                ),

              // 2. The Custom Rehoboam Ring & HUD Labels
              CustomPaint(
                size: Size.square(widget.size),
                painter: _RehoboamPainter(
                  t: _controller.value,
                  transition: _transitionAnim.value,
                  level: widget.level.clamp(0.0, 1.0),
                  mode: widget.mode,
                  speed: widget.speed,
                  centerLabel: widget.centerLabel,
                  topLabel: widget.topLabel,
                  bottomLabel: widget.bottomLabel,
                  targetLat: widget.targetLat,
                  targetLon: widget.targetLon,
                  geoPoints: widget.geoPoints,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RehoboamPainter extends CustomPainter {
  _RehoboamPainter({
    required this.t,
    required this.transition,
    required this.level,
    required this.mode,
    required this.speed,
    this.centerLabel,
    this.topLabel,
    this.bottomLabel,
    this.targetLat,
    this.targetLon,
    this.geoPoints,
  });

  final double t;
  final double transition;
  final double level;
  final AiFaceMode mode;
  final double speed;
  final String? centerLabel;
  final String? topLabel;
  final String? bottomLabel;
  final double? targetLat;
  final double? targetLon;
  final List<Map<String, double>>? geoPoints;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.32;
    final breathing = math.sin(t * 2 * math.pi) * 3.0;

    // Dynamic radius that expands slightly during transition
    final radius = (baseRadius + breathing) * (1.0 + 0.08 * transition);

    // 2. Ring particles (fade out during transition)
    _drawRingParticles(canvas, center, radius);

    // 3. Technical HUD (Always 2D)
    _drawHUD(canvas, center, radius, size);

    // 4. Center System ID (Fades out completely as Earth appears)
    if (transition < 0.2) {
      _drawCenterLabel(canvas, center, 1.0 - (transition * 5.0).clamp(0, 1));
    }
  }

  void _drawRingParticles(Canvas canvas, Offset center, double radius) {
    if (transition > 0.98) return;

    const int segments = 1000;
    final rotation = t * 2 * math.pi * 0.1 * speed;
    final rand = math.Random(42);

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = Colors.white
          .withValues(alpha: (0.8 * (1.0 - transition)).clamp(0, 1));

    for (var i = 0; i < segments; i++) {
      final angle = (i * 2 * math.pi / segments) + rotation;

      // Shape logic: Keep the base perfectly circular
      final baseR = radius;

      // Border logic: Multi-layered noise for the organic texture ONLY
      double noise = _noise(angle, t * 0.5) * (3 + level * 15);
      noise += _noise(angle * 8, t * 1.5) * (1.5 + level * 8);

      // Sharp Divergence Spikes (Texture detail, not shape deviation)
      double divergence = 0.0;
      final divTrigger =
          (math.sin(angle * 1.8 + t * 0.8) * math.cos(angle * 4.2 - t * 0.3))
              .abs();
      if (divTrigger > 0.82) {
        final spikePower = math.pow(divTrigger, 10.0) * (20 + level * 40);
        divergence = math.sin(angle * 50 + t * 12).abs() * spikePower;
      }

      final cloudDensity = 3 + (level * 6).toInt();
      for (var j = 0; j < cloudDensity; j++) {
        // We use the noise/divergence to drive the scattering distance
        // rather than the base path, keeping the overall shape a perfect circle.
        final scatterRange = (noise + divergence).abs();
        final scatter = (1.5 + scatterRange * 0.4) * rand.nextDouble();
        final scatterAngle = angle + (rand.nextDouble() - 0.5) * 0.08;

        // Balanced inward/outward scatter for a thick "ink" border
        final r = baseR + (rand.nextBool() ? scatter : -scatter * 0.8);

        final pos = Offset(
          center.dx + math.cos(scatterAngle) * r,
          center.dy + math.sin(scatterAngle) * r,
        );

        final flicker = 0.6 + 0.4 * rand.nextDouble();
        paint.color = Colors.white.withValues(
          alpha: (0.7 * (1.0 - transition) * flicker).clamp(0, 1),
        );
        paint.strokeWidth = 0.6 + rand.nextDouble() * 0.5;

        canvas.drawPoints(ui.PointMode.points, [pos], paint);
      }
    }
  }

  void _drawCenterLabel(Canvas canvas, Offset center, double opacity) {
    if (centerLabel == null || opacity <= 0) return;
    final style = ui.TextStyle(
      color: Colors.white.withValues(alpha: 0.9 * opacity),
      fontSize: 11,
      fontWeight: ui.FontWeight.w700,
      fontFamily: 'Courier',
      letterSpacing: 3,
    );
    final pb =
        ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
          ..pushStyle(style)
          ..addText(centerLabel!.toUpperCase());
    final paragraph = pb.build()
      ..layout(const ui.ParagraphConstraints(width: 120));
    canvas.drawParagraph(paragraph, Offset(center.dx - 60, center.dy - 6));
  }

  void _drawHUD(Canvas canvas, Offset center, double radius, Size size) {
    if (topLabel != null) {
      _drawDynamicLabel(canvas, center, radius, topLabel!, true, size);
    }
    if (bottomLabel != null) {
      _drawDynamicLabel(canvas, center, radius, bottomLabel!, false, size);
    }
  }

  void _drawDynamicLabel(
    Canvas canvas,
    Offset center,
    double radius,
    String text,
    bool isTop,
    Size size,
  ) {
    final style = ui.TextStyle(
      color: Colors.white.withValues(alpha: 0.9),
      fontSize: 9,
      fontWeight: ui.FontWeight.w400,
      fontFamily: 'Courier',
      height: 1.2,
      letterSpacing: 0.5,
    );
    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.left, maxLines: 10),
    )
      ..pushStyle(style)
      ..addText(text.toUpperCase());
    final double maxWidth = size.width * 0.35;
    final paragraph = pb.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));

    const xPos = 20.0;
    final yPos = isTop ? 25.0 : size.height - paragraph.height - 25.0;
    final labelRoot = Offset(xPos, yPos);

    canvas.drawRect(
      Rect.fromLTWH(
        xPos - 2,
        yPos - 2,
        paragraph.width + 4,
        paragraph.height + 4,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawParagraph(paragraph, labelRoot);

    final leaderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 0.2;
    // Fixed technical angle towards the ring shoulder
    final Offset target = Offset(
      center.dx + math.cos(isTop ? -2.7 : 2.7) * radius,
      center.dy + math.sin(isTop ? -2.7 : 2.7) * radius,
    );

    final path = Path();
    if (isTop) {
      path.moveTo(xPos, yPos + paragraph.height + 4);
      path.lineTo(target.dx, target.dy);
    } else {
      path.moveTo(xPos, yPos - 4);
      path.lineTo(target.dx, target.dy);
    }
    canvas.drawPath(path, leaderPaint);
    canvas.drawCircle(
      target,
      0.6,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  double _noise(double x, double t) {
    return math.sin(x + t) * math.cos(x * 2.3 + t * 0.7) * 0.5 +
        math.sin(x * 4.5 - t * 1.5) * 0.25;
  }

  @override
  bool shouldRepaint(_RehoboamPainter old) => true;
}

/// A reactive pulse marker for cities and earthquakes
class _MarkerPulse extends StatefulWidget {
  const _MarkerPulse({required this.magnitude, this.isSignificant = false});
  final double magnitude;
  final bool isSignificant;

  @override
  State<_MarkerPulse> createState() => _MarkerPulseState();
}

class _MarkerPulseState extends State<_MarkerPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseSize =
        widget.isSignificant ? 12.0 : (widget.magnitude * 2.0).clamp(4.0, 15.0);
    // Use a high-visibility grey that works on both black/white
    const markerColor = Color(0xFFCCCCCC);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Container(
        width: baseSize * 4,
        height: baseSize * 4,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse
            Container(
              width: baseSize * (1 + _ctrl.value),
              height: baseSize * (1 + _ctrl.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: markerColor.withValues(alpha: 0.7 * (1 - _ctrl.value)),
                  width: 1.5,
                ),
              ),
            ),
            // Inner core dot
            Container(
              width: 3.5,
              height: 3.5,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: markerColor, blurRadius: 4, spreadRadius: 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
