import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';

/// A living neural-network backdrop: drifting nodes, distance-faded links
/// and light pulses that hop from synapse to synapse.
///
/// * Node count follows the area ([density] nodes per 100×100 logical px,
///   capped at [maxNodes]), so phones and desktops look equally rich.
/// * The pointer (mouse hover or touch) attracts nearby nodes and wires
///   itself into the network. Events still reach [child].
/// * All buffers are preallocated: a frame does a fixed amount of math and
///   about a dozen draw calls, with no allocations.
/// * Purely decorative: excluded from semantics; [child] is unaffected.
class NeuralNetworkBackground extends StatefulWidget {
  /// Creates the backdrop.
  const NeuralNetworkBackground({
    super.key,
    this.child,
    this.density = 1.0,
    this.maxNodes = 140,
    this.linkDistance = 120,
    this.color,
    this.secondaryColor,
    this.speed = 1,
    this.interactive = true,
    this.pulses = true,
    this.seed = 7,
    this.animate = true,
  });

  /// Content drawn above the network.
  final Widget? child;

  /// Nodes per 10 000 logical px².
  final double density;

  /// Upper bound for the node count.
  final int maxNodes;

  /// Nodes closer than this (logical px) are linked.
  final double linkDistance;

  /// Node / pulse color. Defaults to the theme accent.
  final Color? color;

  /// Link color. Defaults to the theme secondary.
  final Color? secondaryColor;

  /// Drift speed multiplier.
  final double speed;

  /// Pointer attraction.
  final bool interactive;

  /// Light pulses travelling along links.
  final bool pulses;

  /// Layout seed (same seed, same network, on every platform).
  final int seed;

  /// Set to `false` for a still network.
  final bool animate;

  @override
  State<NeuralNetworkBackground> createState() =>
      _NeuralNetworkBackgroundState();
}

/// The simulation state, separated from the widget for testing.
class NeuralNetworkSim {
  /// Allocates buffers for up to [capacity] nodes.
  NeuralNetworkSim(this.capacity, int seed) {
    _seed(seed);
  }

  /// Buffer size.
  final int capacity;

  /// Positions and velocities (logical px, px/s).
  late final Float32List x = Float32List(capacity);

  /// Positions and velocities (logical px, px/s).
  late final Float32List y = Float32List(capacity);

  /// Positions and velocities (logical px, px/s).
  late final Float32List vx = Float32List(capacity);

  /// Positions and velocities (logical px, px/s).
  late final Float32List vy = Float32List(capacity);

  /// Per-node size factor.
  late final Float32List weight = Float32List(capacity);

  /// Pulse endpoints and progress.
  static const int pulseCapacity = 10;

  /// Pulse source node.
  final Int32List pulseFrom = Int32List(pulseCapacity);

  /// Pulse target node.
  final Int32List pulseTo = Int32List(pulseCapacity);

  /// Pulse progress `0..1`.
  final Float32List pulseT = Float32List(pulseCapacity);

  late NeuralRandom _rng;

  /// Active node count.
  int count = 0;

  /// Area the positions are expressed in.
  Size size = Size.zero;

  /// Pointer position, or `null`.
  Offset? pointer;

  void _seed(int seed) {
    _rng = NeuralRandom(hash32([seed, 0x5EED]));
    for (var i = 0; i < capacity; i++) {
      // Unit coordinates until the first layout gives us a size.
      x[i] = _rng.nextDouble();
      y[i] = _rng.nextDouble();
      final a = _rng.nextDouble() * 2 * math.pi;
      final v = 6 + _rng.nextDouble() * 12;
      vx[i] = math.cos(a) * v;
      vy[i] = math.sin(a) * v;
      weight[i] =
          _rng.nextDouble() < 0.12 ? 1.0 : 0.3 + 0.4 * _rng.nextDouble();
    }
    for (var p = 0; p < pulseCapacity; p++) {
      pulseFrom[p] = p;
      pulseTo[p] = p + 1;
      pulseT[p] = _rng.nextDouble();
    }
  }

  /// Adapts to a new layout [s]; node positions scale proportionally.
  void resize(Size s, double density, int maxNodes) {
    if (!s.isFinite || s.isEmpty) return;
    final wanted = (s.width * s.height / 10000 * finiteOr(density, 1))
        .round()
        .clamp(math.min(6, capacity), math.min(maxNodes, capacity));
    if (size.isEmpty) {
      for (var i = 0; i < capacity; i++) {
        x[i] *= s.width;
        y[i] *= s.height;
      }
    } else if (s != size) {
      final kx = s.width / size.width;
      final ky = s.height / size.height;
      for (var i = 0; i < capacity; i++) {
        x[i] *= kx;
        y[i] *= ky;
      }
    }
    size = s;
    count = wanted.toInt();
    for (var p = 0; p < pulseCapacity; p++) {
      pulseFrom[p] %= math.max(1, count);
      pulseTo[p] %= math.max(1, count);
    }
  }

  /// Advances the simulation by [dt] seconds.
  void step(double dt, double linkDistance, {required bool interactive}) {
    if (count == 0 || size.isEmpty || dt <= 0) return;
    final w = size.width;
    final h = size.height;
    final ptr = interactive ? pointer : null;
    final reach = linkDistance * 1.4;
    for (var i = 0; i < count; i++) {
      var nvx = vx[i];
      var nvy = vy[i];
      if (ptr != null) {
        final dx = ptr.dx - x[i];
        final dy = ptr.dy - y[i];
        final d2 = dx * dx + dy * dy;
        if (d2 < reach * reach && d2 > 1) {
          final d = math.sqrt(d2);
          final pull = 60 * (1 - d / reach) * dt;
          nvx += dx / d * pull;
          nvy += dy / d * pull;
        }
      }
      // Relax back toward a calm drift speed.
      final sp = math.sqrt(nvx * nvx + nvy * nvy);
      if (sp > 22) {
        final k = math.max(22 / sp, 1 - 1.5 * dt);
        nvx *= k;
        nvy *= k;
      }
      var nx = x[i] + nvx * dt;
      var ny = y[i] + nvy * dt;
      if (nx < 0) {
        nx = -nx;
        nvx = nvx.abs();
      } else if (nx > w) {
        nx = 2 * w - nx;
        nvx = -nvx.abs();
      }
      if (ny < 0) {
        ny = -ny;
        nvy = nvy.abs();
      } else if (ny > h) {
        ny = 2 * h - ny;
        nvy = -nvy.abs();
      }
      x[i] = nx.clamp(0, w);
      y[i] = ny.clamp(0, h);
      vx[i] = nvx;
      vy[i] = nvy;
    }

    // Pulses hop to a linked neighbour when they arrive.
    final l2 = linkDistance * linkDistance;
    for (var p = 0; p < pulseCapacity; p++) {
      pulseT[p] += dt * 0.6;
      final a = pulseFrom[p];
      final b = pulseTo[p];
      final dx = x[a] - x[b];
      final dy = y[a] - y[b];
      final broken = dx * dx + dy * dy > l2 * 1.2;
      if (pulseT[p] >= 1 || broken || a >= count || b >= count) {
        final from = broken ? a : b;
        pulseFrom[p] = from % count;
        pulseTo[p] = _neighbour(pulseFrom[p], l2);
        pulseT[p] = broken ? _rng.nextDouble() * 0.3 : 0;
      }
    }
  }

  int _neighbour(int i, double l2) {
    // Start at a random offset so pulses spread across the graph.
    final start = (_rng.nextDouble() * count).floor();
    for (var k = 0; k < count; k++) {
      final j = (start + k) % count;
      if (j == i) continue;
      final dx = x[i] - x[j];
      final dy = y[i] - y[j];
      if (dx * dx + dy * dy < l2) return j;
    }
    return (i + 1) % count;
  }
}

class _NeuralNetworkBackgroundState extends State<NeuralNetworkBackground>
    with SingleTickerProviderStateMixin {
  static const int _capacity = 240;
  late NeuralNetworkSim _sim = NeuralNetworkSim(_capacity, widget.seed);
  late final NeuralClock _clock = NeuralClock(this, speed: widget.speed)
    ..onTick = (dt) => _sim.step(
          dt,
          finiteOr(widget.linkDistance, 120).clamp(10, 600),
          interactive: widget.interactive,
        );
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotionOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(NeuralNetworkBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) {
      final size = _sim.size;
      _sim = NeuralNetworkSim(_capacity, widget.seed)
        ..resize(size, widget.density, widget.maxNodes);
    } else if (oldWidget.density != widget.density ||
        oldWidget.maxNodes != widget.maxNodes) {
      _sim.resize(_sim.size, widget.density, widget.maxNodes);
    }
    _sync();
  }

  void _sync() {
    _clock.speed = widget.speed;
    _clock.setRunning(widget.animate && !_reduce && _clock.speed > 0);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _point(Offset? p) {
    if (!widget.interactive) return;
    _sim.pointer = p;
    if (!_clock.isRunning) _clock.advance(0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = NeuralPalette.of(
      context,
      accent: widget.color,
      secondary: widget.secondaryColor,
    );
    final network = LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest;
        _sim.resize(size, widget.density, widget.maxNodes);
        return ExcludeSemantics(
          child: RepaintBoundary(
            child: CustomPaint(
              size: size.isFinite ? size : Size.zero,
              painter: NeuralNetworkPainter(
                clock: _clock,
                sim: _sim,
                palette: palette,
                linkDistance: finiteOr(widget.linkDistance, 120).clamp(10, 600),
                pulses: widget.pulses,
              ),
            ),
          ),
        );
      },
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (e) => _point(e.localPosition),
      onPointerDown: (e) => _point(e.localPosition),
      onPointerMove: (e) => _point(e.localPosition),
      onPointerUp: (_) => _point(null),
      onPointerCancel: (_) => _point(null),
      child: MouseRegion(
        opaque: false,
        onExit: (_) => _point(null),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(child: network),
            if (widget.child != null)
              widget.child!
            else
              const SizedBox.expand(),
          ],
        ),
      ),
    );
  }
}

/// Paints [NeuralNetworkBackground].
class NeuralNetworkPainter extends CustomPainter {
  /// Creates the painter.
  NeuralNetworkPainter({
    required this.clock,
    required this.sim,
    required this.palette,
    required this.linkDistance,
    required this.pulses,
  }) : super(repaint: clock);

  /// Frame clock.
  final ValueListenable<double> clock;

  /// Simulation.
  final NeuralNetworkSim sim;

  /// Colors.
  final NeuralPalette palette;

  /// Link radius.
  final double linkDistance;

  /// Draw pulses.
  final bool pulses;

  static const int _buckets = 4;
  static const int _maxLinksPerBucket = 1500;
  static final List<Float32List> _lines =
      List.generate(_buckets, (_) => Float32List(_maxLinksPerBucket * 4));
  static final Float32List _nodes = Float32List(480);
  static final Float32List _hubs = Float32List(480);
  final List<int> _counts = List.filled(_buckets, 0);
  final Paint _line = Paint()..strokeCap = StrokeCap.round;
  final Paint _dot = Paint()..strokeCap = StrokeCap.round;
  final Paint _fill = Paint();
  ui.Shader? _halo;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final n = sim.count;
    if (n == 0) return;
    final x = sim.x;
    final y = sim.y;
    final l = linkDistance;
    final l2 = l * l;
    final dark = palette.isDark;
    final linkBase = dark ? 0.55 : 0.42;
    for (var b = 0; b < _buckets; b++) {
      _counts[b] = 0;
    }

    // Links, bucketed by strength so ~4 draw calls render them all.
    for (var i = 0; i < n; i++) {
      final xi = x[i];
      final yi = y[i];
      for (var j = i + 1; j < n; j++) {
        final dx = xi - x[j];
        if (dx > l || dx < -l) continue;
        final dy = yi - y[j];
        final d2 = dx * dx + dy * dy;
        if (d2 >= l2) continue;
        final strength = 1 - math.sqrt(d2) / l; // 0..1
        final b = (strength * _buckets).floor().clamp(0, _buckets - 1);
        final k = _counts[b];
        if (k >= _maxLinksPerBucket * 4) continue;
        final buf = _lines[b];
        buf[k] = xi;
        buf[k + 1] = yi;
        buf[k + 2] = x[j];
        buf[k + 3] = y[j];
        _counts[b] = k + 4;
      }
    }
    for (var b = 0; b < _buckets; b++) {
      if (_counts[b] == 0) continue;
      final s = (b + 0.5) / _buckets;
      _line
        ..color = palette.secondary.withValues(alpha: linkBase * s * s)
        ..strokeWidth = 0.6 + 0.8 * s;
      canvas.drawRawPoints(ui.PointMode.lines,
          Float32List.sublistView(_lines[b], 0, _counts[b]), _line);
    }

    // Pointer wiring.
    final ptr = sim.pointer;
    if (ptr != null) {
      final reach = l * 1.4;
      for (var i = 0; i < n; i++) {
        final dx = x[i] - ptr.dx;
        final dy = y[i] - ptr.dy;
        final d2 = dx * dx + dy * dy;
        if (d2 < reach * reach) {
          final s = 1 - math.sqrt(d2) / reach;
          _line
            ..color = palette.accent.withValues(alpha: 0.6 * s)
            ..strokeWidth = 0.8 + s;
          canvas.drawLine(ptr, Offset(x[i], y[i]), _line);
        }
      }
      _fill.color = palette.accent.withValues(alpha: 0.9);
      canvas.drawCircle(ptr, 3, _fill);
    }

    // Nodes: small ones in one call, hubs with a halo.
    var nc = 0;
    var hc = 0;
    for (var i = 0; i < n; i++) {
      if (sim.weight[i] >= 1) {
        _hubs[hc++] = x[i];
        _hubs[hc++] = y[i];
      } else {
        _nodes[nc++] = x[i];
        _nodes[nc++] = y[i];
      }
    }
    _dot
      ..color = palette.accent.withValues(alpha: dark ? 0.85 : 0.75)
      ..strokeWidth = 2.6;
    if (nc > 0) {
      canvas.drawRawPoints(
          ui.PointMode.points, Float32List.sublistView(_nodes, 0, nc), _dot);
    }
    if (hc > 0) {
      _halo ??= ui.Gradient.radial(Offset.zero, 1, [
        palette.accent
            .withValues(alpha: 0.45 * palette.glowIntensity.clamp(0, 1)),
        palette.accent.withValues(alpha: 0),
      ]);
      final pulse = 0.85 + 0.15 * math.sin(clock.value * 2.2);
      for (var k = 0; k < hc; k += 2) {
        canvas.save();
        canvas.translate(_hubs[k], _hubs[k + 1]);
        canvas.scale(14 * pulse);
        _fill
          ..shader = _halo
          ..color = const Color(0xFF000000);
        canvas.drawCircle(Offset.zero, 1, _fill);
        canvas.restore();
      }
      _fill.shader = null;
      _dot
        ..color = Color.lerp(palette.accent, Colors.white, dark ? 0.5 : 0.1)!
        ..strokeWidth = 4.5;
      canvas.drawRawPoints(
          ui.PointMode.points, Float32List.sublistView(_hubs, 0, hc), _dot);
    }

    // Pulses.
    if (pulses) {
      for (var p = 0; p < NeuralNetworkSim.pulseCapacity; p++) {
        final a = sim.pulseFrom[p];
        final b = sim.pulseTo[p];
        if (a >= n || b >= n) continue;
        final t = sim.pulseT[p].clamp(0.0, 1.0);
        final px = x[a] + (x[b] - x[a]) * t;
        final py = y[a] + (y[b] - y[a]) * t;
        final fade = math.sin(t * math.pi);
        _fill.color = palette.accent.withValues(alpha: 0.28 * fade);
        canvas.drawCircle(Offset(px, py), 6, _fill);
        _fill.color = Color.lerp(palette.accent, Colors.white, 0.6)!
            .withValues(alpha: fade);
        canvas.drawCircle(Offset(px, py), 2, _fill);
      }
    }
  }

  @override
  bool shouldRepaint(NeuralNetworkPainter old) =>
      old.clock != clock ||
      old.sim != sim ||
      old.palette != palette ||
      old.linkDistance != linkDistance ||
      old.pulses != pulses;
}
