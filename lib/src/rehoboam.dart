import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dot_globe/dot_globe.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/neural_clock.dart';

/// The visual state of the HUD.
enum HudMode {
  /// The organic particulate data ring.
  ring,

  /// The ring dissolves into a rotating dotted Earth with markers.
  earth,
}

/// Whether the HUD is listening (calm) or speaking (energetic).
enum AiFaceMode {
  /// Calm texture driven by [AiThinkingAnimation.level].
  listening,

  /// Faster, spikier texture for when the assistant talks.
  speaking,
}

/// A high-fidelity "Rehoboam" (Westworld style) data-ring and 3D globe.
///
/// The ring is a cloud of a few thousand particles whose ink-like border
/// reacts to [level]. Switching [hudMode] to [HudMode.earth] dissolves the
/// ring into a dotted globe that flies to [targetLat] / [targetLon] and
/// pulses a marker for every entry in [geoPoints].
///
/// Honors `MediaQuery.disableAnimations` (shows a still frame and switches
/// modes instantly) and mirrors the HUD labels in right-to-left locales.
class AiThinkingAnimation extends StatefulWidget {
  /// Creates the Rehoboam HUD.
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
    this.color = Colors.white,
    this.semanticsLabel,
    this.animate = true,
  });

  /// Input energy, `0..1` (mic level, model confidence, load...).
  final double level;

  /// Listening (calm) or speaking (energetic) texture.
  final AiFaceMode mode;

  /// Ring or Earth view.
  final HudMode hudMode;

  /// Side of the square HUD in logical pixels. A non-finite value fills the
  /// incoming constraints instead.
  final double size;

  /// Animation speed multiplier (`0` freezes the ring).
  final double speed;

  /// Text in the middle of the ring (fades out in Earth mode).
  final String? centerLabel;

  /// Technical caption in the top corner.
  final String? topLabel;

  /// Technical caption in the bottom corner.
  final String? bottomLabel;

  /// Latitude the globe flies to in Earth mode.
  final double? targetLat;

  /// Longitude the globe flies to in Earth mode.
  final double? targetLon;

  /// Extra markers: `{'lat': .., 'lon': .., 'mag': ..}`. `mag` is optional.
  final List<Map<String, double>>? geoPoints;

  /// Drives the globe. One is created internally when omitted, so the
  /// fly-to-target zoom always works.
  final DotGlobeController? dotGlobeController;

  /// Globe colors.
  final DotGlobeStyle dotGlobeStyle;

  /// Ring particle and label color. Defaults to white (the HUD is designed
  /// for dark backdrops); pass `Theme.of(context).colorScheme.onSurface` to
  /// follow the theme.
  final Color color;

  /// Accessibility label. Defaults to the visible labels.
  final String? semanticsLabel;

  /// Set to `false` to show a still frame.
  final bool animate;

  @override
  State<AiThinkingAnimation> createState() => _AiThinkingAnimationState();
}

class _AiThinkingAnimationState extends State<AiThinkingAnimation>
    with TickerProviderStateMixin {
  late final NeuralClock _clock;
  late final AnimationController _transitionController;
  late final Animation<double> _transitionAnim;
  late final Animation<double> _globeScale;

  DotGlobeController? _ownGlobeController;
  late HudMode _lastMode;
  bool _pendingFly = false;
  bool _reduceMotion = false;
  List<DotGlobeMarker> _markers = const [];

  DotGlobeController get _globeController =>
      widget.dotGlobeController ??
      (_ownGlobeController ??= DotGlobeController());

  @override
  void initState() {
    super.initState();
    _clock = NeuralClock(this, speed: widget.speed);
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
      // Respect the initial mode: an HUD created in Earth mode starts there.
      value: widget.hudMode == HudMode.earth ? 1 : 0,
    )..addStatusListener(_onTransitionStatus);
    _transitionAnim = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeInOutQuart,
    );
    _globeScale = Tween<double>(begin: 0.9, end: 1).animate(_transitionAnim);
    _lastMode = widget.hudMode;
    _pendingFly = widget.hudMode == HudMode.earth;
    _markers = _buildMarkers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = reduceMotionOf(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      _markers = _buildMarkers();
    }
    _syncClock();
  }

  void _syncClock() {
    _clock.speed = widget.speed;
    _clock.setRunning(widget.animate && !_reduceMotion && widget.speed > 0);
  }

  void _onTransitionStatus(AnimationStatus status) {
    // Mount / unmount the globe only at the ends of the transition.
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AiThinkingAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
    if (widget.dotGlobeController != null && _ownGlobeController != null) {
      _ownGlobeController!.dispose();
      _ownGlobeController = null;
    }
    if (widget.hudMode != _lastMode) {
      _lastMode = widget.hudMode;
      final toEarth = widget.hudMode == HudMode.earth;
      if (_reduceMotion) {
        _transitionController.value = toEarth ? 1 : 0;
      } else if (toEarth) {
        _transitionController.forward();
      } else {
        _transitionController.reverse();
      }
      // The globe is not mounted yet (its controller is detached), so the
      // flight must wait until after the next frame.
      if (toEarth) _pendingFly = true;
    } else if (widget.hudMode == HudMode.earth &&
        (widget.targetLat != oldWidget.targetLat ||
            widget.targetLon != oldWidget.targetLon)) {
      _pendingFly = true;
    }
    if (!identical(widget.geoPoints, oldWidget.geoPoints) ||
        widget.targetLat != oldWidget.targetLat ||
        widget.targetLon != oldWidget.targetLon) {
      _markers = _buildMarkers();
    }
  }

  bool get _hasTarget =>
      widget.targetLat != null &&
      widget.targetLon != null &&
      widget.targetLat!.isFinite &&
      widget.targetLon!.isFinite;

  void _schedulePendingFly() {
    if (!_pendingFly) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pendingFly) return;
      _pendingFly = false;
      if (!_hasTarget) return;
      final controller = _globeController;
      if (!controller.isAttached) return;
      if (_reduceMotion) {
        controller.jumpTo(
          latitude: widget.targetLat!,
          longitude: widget.targetLon!,
          scale: 1.8,
        );
      } else {
        controller.animateTo(
          latitude: widget.targetLat!,
          longitude: widget.targetLon!,
          scale: 1.8,
          duration: const Duration(milliseconds: 1800),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  List<DotGlobeMarker> _buildMarkers() {
    final markers = <DotGlobeMarker>[];
    final animate = !_reduceMotion;

    if (_hasTarget) {
      markers.add(
        DotGlobeMarker(
          latitude: widget.targetLat!,
          longitude: widget.targetLon!,
          child: _MarkerPulse(
            magnitude: 6.0,
            isSignificant: true,
            animate: animate,
          ),
        ),
      );
    }

    final points = widget.geoPoints;
    if (points != null && points.isNotEmpty) {
      var maxMag = 1.0;
      for (final p in points) {
        final m = p['mag'] ?? 1.0;
        if (m.isFinite && m > maxMag) maxMag = m;
      }
      for (final point in points) {
        final lat = point['lat'];
        final lon = point['lon'];
        var mag = point['mag'] ?? 1.0;
        if (!mag.isFinite) mag = 1.0;
        if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
          continue;
        }
        // Skip the target city itself to avoid a double marker.
        if (lat == widget.targetLat && lon == widget.targetLon) continue;
        markers.add(
          DotGlobeMarker(
            latitude: lat.clamp(-90.0, 90.0),
            longitude: lon,
            child: _MarkerPulse(
              magnitude: mag,
              isSignificant: mag >= maxMag && mag > 4.0,
              animate: animate,
            ),
          ),
        );
      }
    }
    return markers;
  }

  @override
  void dispose() {
    _transitionController.dispose();
    _clock.dispose();
    _ownGlobeController?.dispose();
    super.dispose();
  }

  Widget _buildHud(double dimension) {
    final dir = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final globeMounted =
        _transitionController.status != AnimationStatus.dismissed;
    if (globeMounted) _schedulePendingFly();

    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (globeMounted)
            ExcludeSemantics(
              child: FadeTransition(
                opacity: _transitionAnim,
                child: ScaleTransition(
                  scale: _globeScale,
                  child: Center(
                    // Clipped to a lens: the fly-to zoom (1.8x) would
                    // otherwise spill the sphere over neighbouring UI.
                    child: SizedBox.square(
                      dimension: dimension * 0.7,
                      child: ClipOval(
                        child: DotGlobe(
                          controller: _globeController,
                          style: widget.dotGlobeStyle,
                          initialLatitude: _hasTarget
                              ? widget.targetLat!.clamp(-90.0, 90.0)
                              : 0,
                          initialLongitude: _hasTarget ? widget.targetLon! : 0,
                          paused: _reduceMotion || !widget.animate,
                          markers: _markers,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          RepaintBoundary(
            child: CustomPaint(
              painter: _RehoboamPainter(
                clock: _clock,
                transition: _transitionAnim,
                level: unit(widget.level),
                mode: widget.mode,
                color: widget.color,
                textDirection: dir,
                centerLabel: widget.centerLabel,
                topLabel: widget.topLabel,
                bottomLabel: widget.bottomLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.semanticsLabel ??
        [widget.centerLabel, widget.topLabel, widget.bottomLabel]
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .join('. ');
    final size = widget.size;
    final Widget hud = size.isFinite
        ? _buildHud(math.max(0, size))
        : LayoutBuilder(
            builder: (context, c) {
              final side = c.biggest.shortestSide;
              return _buildHud(side.isFinite ? side : 320);
            },
          );
    return Semantics(
      container: true,
      image: true,
      label: label.isEmpty ? 'Neural HUD' : label,
      child: ExcludeSemantics(child: hud),
    );
  }
}

class _RehoboamPainter extends CustomPainter {
  _RehoboamPainter({
    required this.clock,
    required this.transition,
    required this.level,
    required this.mode,
    required this.color,
    required this.textDirection,
    this.centerLabel,
    this.topLabel,
    this.bottomLabel,
  }) : super(repaint: Listenable.merge([clock, transition]));

  final ValueListenable<double> clock;
  final Animation<double> transition;
  final double level;
  final AiFaceMode mode;
  final Color color;
  final TextDirection textDirection;
  final String? centerLabel;
  final String? topLabel;
  final String? bottomLabel;

  static const int _segments = 1000;
  static const int _maxCloud = 9;
  static const int _buckets = 3;

  // Preallocated point buffers (one per alpha/width bucket): the ring draws
  // ~9000 particles per frame with three draw calls and no allocations.
  static final List<Float32List> _buffers = List.generate(
    _buckets,
    (_) => Float32List(_segments * _maxCloud * 2),
  );
  final List<int> _counts = List.filled(_buckets, 0);
  final NeuralRandom _rng = NeuralRandom(42);
  final Paint _pointPaint = Paint()..strokeCap = StrokeCap.round;

  ui.Paragraph? _center;
  ui.Paragraph? _top;
  ui.Paragraph? _bottom;
  double _labelWidth = -1;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    final s = clock.value; // seconds, never wraps
    final tr = transition.value;
    final center = size.center(Offset.zero);
    final baseRadius = size.shortestSide * 0.32;
    final breathing =
        math.sin(s * 2 * math.pi / 30) * 3.0 * (size.shortestSide / 320);
    final radius = (baseRadius + breathing) * (1.0 + 0.08 * tr);

    _drawRingParticles(canvas, center, radius, s, tr, size.shortestSide / 320);
    _drawHUD(canvas, center, radius, size);
    if (tr < 0.2) {
      _drawCenterLabel(canvas, center, 1.0 - (tr * 5.0).clamp(0.0, 1.0));
    }
  }

  void _drawRingParticles(
    Canvas canvas,
    Offset center,
    double radius,
    double s,
    double tr,
    double scale,
  ) {
    if (tr > 0.98) return;
    final speaking = mode == AiFaceMode.speaking;
    final energy = (level * (speaking ? 1.35 : 1.0)).clamp(0.0, 1.35);
    // Seconds -> the original "30 s cycle" phase, advanced faster when
    // speaking. Continuous, so there is no jump at any loop point.
    final t = s / 30 * (speaking ? 1.6 : 1.0);
    final rotation = s * 2 * math.pi * 0.1 / 30;
    final cloudDensity = 3 + (energy * 6).clamp(0, 6).toInt();
    _rng.reseed(42);
    for (var b = 0; b < _buckets; b++) {
      _counts[b] = 0;
    }

    for (var i = 0; i < _segments; i++) {
      // Texture uses integer harmonics of the base angle so it is seamless
      // around the circle; rotation only moves where it is drawn.
      final theta = i * 2 * math.pi / _segments;
      final angle = theta + rotation;

      var noise = _noise(theta, t * 0.5) * (3 + energy * 15);
      noise += _noise(theta * 8, t * 1.5) * (1.5 + energy * 8);

      var divergence = 0.0;
      final divTrigger =
          (math.sin(theta * 2 + t * 0.8) * math.cos(theta * 4 - t * 0.3)).abs();
      if (divTrigger > 0.82) {
        final spikePower =
            math.pow(divTrigger, 10.0).toDouble() * (20 + energy * 40);
        divergence = math.sin(theta * 50 + t * 12).abs() * spikePower;
      }
      final scatterRange = (noise + divergence).abs() * scale;

      for (var j = 0; j < cloudDensity; j++) {
        final scatter = (1.5 * scale + scatterRange * 0.4) * _rng.nextDouble();
        final scatterAngle = angle + (_rng.nextDouble() - 0.5) * 0.08;
        final r = radius + (_rng.nextDouble() < 0.5 ? scatter : -scatter * 0.8);
        final b = (_rng.nextDouble() * _buckets).floor().clamp(0, _buckets - 1);
        final buf = _buffers[b];
        final k = _counts[b];
        buf[k] = center.dx + math.cos(scatterAngle) * r;
        buf[k + 1] = center.dy + math.sin(scatterAngle) * r;
        _counts[b] = k + 2;
      }
    }

    for (var b = 0; b < _buckets; b++) {
      if (_counts[b] == 0) continue;
      final flicker = 0.6 + 0.4 * (b + 0.5) / _buckets;
      _pointPaint
        ..color = color.withValues(
          alpha: (color.a * 0.7 * (1.0 - tr) * flicker).clamp(0.0, 1.0),
        )
        ..strokeWidth = (0.6 + 0.5 * (b + 0.5) / _buckets) * scale.clamp(1, 3);
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.sublistView(_buffers[b], 0, _counts[b]),
        _pointPaint,
      );
    }
  }

  ui.Paragraph _paragraph(
    String text,
    double fontSize,
    FontWeight weight,
    double width,
    double letterSpacing,
    TextAlign align,
  ) {
    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: align,
        textDirection: textDirection,
        maxLines: 10,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: color.withValues(alpha: 0.9 * color.a),
          fontSize: fontSize,
          fontWeight: weight,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Courier', 'Roboto Mono', 'Menlo'],
          height: 1.2,
          letterSpacing: letterSpacing,
        ),
      )
      ..addText(text.toUpperCase());
    return pb.build()..layout(ui.ParagraphConstraints(width: width));
  }

  void _ensureLabels(Size size) {
    final width = math.max(1.0, size.width * 0.35);
    if (width == _labelWidth) return;
    _labelWidth = width;
    _center = centerLabel == null
        ? null
        : _paragraph(centerLabel!, 11, FontWeight.w700,
            math.max(1.0, size.width * 0.5), 3, TextAlign.center);
    _top = topLabel == null
        ? null
        : _paragraph(
            topLabel!, 9, FontWeight.w400, width, 0.5, TextAlign.start);
    _bottom = bottomLabel == null
        ? null
        : _paragraph(
            bottomLabel!, 9, FontWeight.w400, width, 0.5, TextAlign.start);
  }

  void _drawCenterLabel(Canvas canvas, Offset center, double opacity) {
    final p = _center;
    if (p == null || opacity <= 0) return;
    if (opacity >= 1) {
      canvas.drawParagraph(
        p,
        Offset(center.dx - p.width / 2, center.dy - p.height / 2),
      );
      return;
    }
    canvas.saveLayer(
      null,
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)),
    );
    canvas.drawParagraph(
      p,
      Offset(center.dx - p.width / 2, center.dy - p.height / 2),
    );
    canvas.restore();
  }

  void _drawHUD(Canvas canvas, Offset center, double radius, Size size) {
    _ensureLabels(size);
    if (_top != null) _drawLabel(canvas, center, radius, _top!, true, size);
    if (_bottom != null) {
      _drawLabel(canvas, center, radius, _bottom!, false, size);
    }
  }

  void _drawLabel(
    Canvas canvas,
    Offset center,
    double radius,
    ui.Paragraph paragraph,
    bool isTop,
    Size size,
  ) {
    final rtl = textDirection == TextDirection.rtl;
    const margin = 20.0;
    final w = paragraph.longestLine.clamp(0.0, paragraph.width);
    final x = rtl ? size.width - margin - w : margin;
    final y = isTop ? 25.0 : size.height - paragraph.height - 25.0;
    final lightInk = color.computeLuminance() > 0.5;

    canvas.drawRect(
      Rect.fromLTWH(x - 2, y - 2, w + 4, paragraph.height + 4),
      Paint()
        ..color =
            (lightInk ? Colors.black : Colors.white).withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // In RTL the paragraph is right-aligned within its layout width.
    canvas.drawParagraph(
      paragraph,
      Offset(rtl ? size.width - margin - paragraph.width : margin, y),
    );

    // Leader line towards the ring shoulder (mirrored in RTL).
    final a = isTop ? -2.7 : 2.7;
    final target = Offset(
      center.dx + (rtl ? -math.cos(a) : math.cos(a)) * radius,
      center.dy + math.sin(a) * radius,
    );
    final anchor = Offset(
      rtl ? x + w : x,
      isTop ? y + paragraph.height + 4 : y - 4,
    );
    canvas.drawLine(
      anchor,
      target,
      Paint()
        ..color = color.withValues(alpha: 0.2 * color.a)
        ..strokeWidth = 0.5,
    );
    canvas.drawCircle(
      target,
      0.8,
      Paint()..color = color.withValues(alpha: 0.5 * color.a),
    );
  }

  static double _noise(double x, double t) {
    // Integer frequency multipliers keep the texture 2π-periodic.
    return math.sin(x + t) * math.cos(x * 2 + t * 0.7) * 0.5 +
        math.sin(x * 5 - t * 1.5) * 0.25;
  }

  @override
  bool shouldRepaint(_RehoboamPainter old) =>
      old.clock != clock ||
      old.transition != transition ||
      old.level != level ||
      old.mode != mode ||
      old.color != color ||
      old.textDirection != textDirection ||
      old.centerLabel != centerLabel ||
      old.topLabel != topLabel ||
      old.bottomLabel != bottomLabel;
}

/// A reactive pulse marker for cities and earthquakes.
class _MarkerPulse extends StatefulWidget {
  const _MarkerPulse({
    required this.magnitude,
    this.isSignificant = false,
    this.animate = true,
  });
  final double magnitude;
  final bool isSignificant;
  final bool animate;

  @override
  State<_MarkerPulse> createState() => _MarkerPulseState();
}

class _MarkerPulseState extends State<_MarkerPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
    value: 0.35,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_MarkerPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.animate && _ctrl.isAnimating) {
      _ctrl.stop();
    }
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
    const markerColor = Color(0xFFCCCCCC);
    return SizedBox.square(
      dimension: baseSize * 4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => Container(
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
          ),
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
    );
  }
}
