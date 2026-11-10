import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';

/// Presence of a [NeuralAvatar]'s user.
enum NeuralPresence {
  /// Available: a turning aura in the success color.
  online,

  /// Idle: a slow amber aura.
  away,

  /// Do not disturb: a red aura.
  busy,

  /// Offline: a faint static ring, no badge glow.
  offline,
}

/// An avatar with a living presence aura, speaking ripples and a status
/// badge.
///
/// * Shows [image] when it loads; otherwise (or on error) the [name]'s
///   initials on a gradient. Initials are grapheme-aware, so emoji and
///   non-Latin scripts are never split.
/// * [speaking] emits ripples scaled by [level], for voice rooms and
///   calls.
/// * The badge sits at the bottom-end corner (bottom-left in RTL).
/// * Announced as "name, presence" (plus ", speaking").
class NeuralAvatar extends StatefulWidget {
  /// Creates an avatar.
  const NeuralAvatar({
    super.key,
    this.image,
    this.name = '',
    this.size = 56,
    this.presence = NeuralPresence.online,
    this.speaking = false,
    this.level = 0,
    this.auraColor,
    this.showBadge = true,
    this.onTap,
    this.semanticsLabel,
    this.presenceLabels = const {
      NeuralPresence.online: 'online',
      NeuralPresence.away: 'away',
      NeuralPresence.busy: 'busy',
      NeuralPresence.offline: 'offline',
    },
  });

  /// Photo. Falls back to initials while loading and on error.
  final ImageProvider? image;

  /// Display name (initials and semantics).
  final String name;

  /// Outer diameter including the aura.
  final double size;

  /// Presence.
  final NeuralPresence presence;

  /// Emit voice ripples.
  final bool speaking;

  /// Voice level `0..1` (ripple strength).
  final double level;

  /// Aura color. Defaults to the presence color.
  final Color? auraColor;

  /// Show the presence badge.
  final bool showBadge;

  /// Makes the avatar a button.
  final VoidCallback? onTap;

  /// Overrides the announced label.
  final String? semanticsLabel;

  /// Announced presence words (localize these).
  final Map<NeuralPresence, String> presenceLabels;

  /// Up to two initials for [name] (grapheme-aware).
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '';
    final first = words.first.characters.first;
    if (words.length == 1) return first.toUpperCase();
    return (first + words.last.characters.first).toUpperCase();
  }

  @override
  State<NeuralAvatar> createState() => _NeuralAvatarState();
}

class _NeuralAvatarState extends State<NeuralAvatar>
    with SingleTickerProviderStateMixin {
  late final NeuralClock _clock = NeuralClock(this);
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotionOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(NeuralAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final alive = widget.presence != NeuralPresence.offline || widget.speaking;
    _clock.setRunning(alive && !_reduce);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  Color _presenceColor(NeuralPalette p) => switch (widget.presence) {
        NeuralPresence.online => p.success,
        NeuralPresence.away => p.warning,
        NeuralPresence.busy => p.error,
        NeuralPresence.offline => p.foreground.withValues(alpha: 0.35),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = NeuralPalette.of(context);
    final size = finiteOr(widget.size, 56).clamp(0.0, double.maxFinite);
    final presenceColor = _presenceColor(palette);
    final aura = widget.auraColor ?? presenceColor;
    final inner = size * 0.76;
    final initials = NeuralAvatar.initialsOf(widget.name);

    Widget fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.secondary, palette.accent],
        ),
      ),
      child: Center(
        child: initials.isEmpty
            ? Icon(Icons.person_rounded,
                size: inner * 0.55, color: theme.colorScheme.onPrimary)
            : Padding(
                padding: EdgeInsets.all(inner * 0.14),
                child: FittedBox(
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
      ),
    );
    fallback = SizedBox.expand(child: fallback);
    final face = widget.image == null
        ? fallback
        : Image(
            image: widget.image!,
            fit: BoxFit.cover,
            width: inner,
            height: inner,
            frameBuilder: (context, child, frame, sync) =>
                frame == null && !sync ? fallback : child,
            errorBuilder: (context, error, stack) => fallback,
          );

    Widget avatar = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: NeuralAuraPainter(
                  clock: _clock,
                  color: aura,
                  accent: palette.accent,
                  presence: widget.presence,
                  speaking: widget.speaking,
                  level: unit(widget.level),
                  glow: palette.glowIntensity,
                ),
              ),
            ),
          ),
          SizedBox.square(
            dimension: inner,
            child: ClipOval(child: face),
          ),
          if (widget.showBadge)
            PositionedDirectional(
              end: size * 0.07,
              bottom: size * 0.07,
              child: Container(
                width: math.max(8, size * 0.2),
                height: math.max(8, size * 0.2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: presenceColor.withValues(alpha: 1),
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: math.max(1.5, size * 0.035),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.onTap != null) {
      avatar = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: widget.onTap, child: avatar),
      );
    }
    final presenceWord =
        widget.presenceLabels[widget.presence] ?? widget.presence.name;
    final label = widget.semanticsLabel ??
        [
          if (widget.name.trim().isNotEmpty) widget.name.trim(),
          presenceWord,
          if (widget.speaking) 'speaking',
        ].join(', ');
    return Semantics(
      container: true,
      button: widget.onTap != null,
      onTap: widget.onTap,
      label: label,
      child: ExcludeSemantics(child: avatar),
    );
  }
}

/// Paints [NeuralAvatar]'s aura and ripples.
class NeuralAuraPainter extends CustomPainter {
  /// Creates the painter.
  NeuralAuraPainter({
    required this.clock,
    required this.color,
    required this.accent,
    required this.presence,
    required this.speaking,
    required this.level,
    required this.glow,
  }) : super(repaint: clock);

  /// Frame clock.
  final ValueListenable<double> clock;

  /// Aura color.
  final Color color;

  /// Secondary sweep color.
  final Color accent;

  /// Presence (offline = static).
  final NeuralPresence presence;

  /// Ripples on.
  final bool speaking;

  /// Ripple level.
  final double level;

  /// Glow multiplier.
  final double glow;

  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  ui.Shader? _sweep;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final s = clock.value;
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.76;
    final ringR = inner + (outer - inner) * 0.42;
    final sw = math.max(1.5, (outer - inner) * 0.32);

    // Speaking ripples (behind the ring).
    if (speaking) {
      for (var k = 0; k < 3; k++) {
        final f = ((s * 0.9) + k / 3) % 1.0;
        _ring
          ..shader = null
          ..strokeWidth = sw * (1 - f) + 0.5
          ..color = color.withValues(alpha: (0.25 + 0.5 * level) * (1 - f));
        canvas.drawCircle(
            c, inner + (outer - inner + outer * 0.25 * level) * f, _ring);
      }
    }

    if (presence == NeuralPresence.offline) {
      _ring
        ..shader = null
        ..strokeWidth = sw * 0.7
        ..color = color;
      canvas.drawCircle(c, ringR, _ring);
      return;
    }

    if (glow > 0) {
      _ring
        ..shader = null
        ..strokeWidth = sw * 2
        ..color = color.withValues(alpha: (0.3 * glow).clamp(0, 1))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sw);
      canvas.drawCircle(c, ringR, _ring);
      _ring.maskFilter = null;
    }
    _sweep ??= ui.Gradient.sweep(Offset.zero, [
      color.withValues(alpha: 0.35),
      color,
      Color.lerp(color, accent, 0.5)!,
      color.withValues(alpha: 0.35),
    ], const [
      0,
      0.35,
      0.7,
      1
    ]);
    final rate = presence == NeuralPresence.away ? 0.35 : 1.1;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(s * rate);
    _ring
      ..shader = _sweep
      ..strokeWidth = sw
      ..color = const Color(0xFF000000);
    canvas.drawCircle(Offset.zero, ringR, _ring);
    canvas.restore();
    _ring.shader = null;
  }

  @override
  bool shouldRepaint(NeuralAuraPainter old) =>
      old.clock != clock ||
      old.color != color ||
      old.accent != accent ||
      old.presence != presence ||
      old.speaking != speaking ||
      old.level != level ||
      old.glow != glow;
}
