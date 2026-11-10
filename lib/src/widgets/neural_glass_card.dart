import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';

/// A frosted-glass panel with a living "neural current" running around its
/// border and a soft glow that brightens on hover, focus and press.
///
/// * Backdrop blur for true glassmorphism (works on every platform; set
///   [blur] to `0` to skip the backdrop pass on very low-end devices).
/// * With [onTap] it becomes a real button: keyboard focusable, activates
///   with Enter / Space, shows a focus glow, and announces as a button.
/// * The border current pauses when animations are disabled.
class NeuralGlassCard extends StatefulWidget {
  /// Creates a glass card.
  const NeuralGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 24,
    this.blur = 18,
    this.tint,
    this.color,
    this.secondaryColor,
    this.glow = true,
    this.animateBorder = true,
    this.borderWidth = 1.4,
    this.onTap,
    this.semanticsLabel,
  });

  /// Card content.
  final Widget child;

  /// Inner padding.
  final EdgeInsetsGeometry padding;

  /// Corner radius.
  final double borderRadius;

  /// Backdrop blur sigma (`0` disables the backdrop filter).
  final double blur;

  /// Glass fill. Defaults to a translucent theme surface.
  final Color? tint;

  /// Border current color. Defaults to the theme accent.
  final Color? color;

  /// Border current tail color. Defaults to the theme secondary.
  final Color? secondaryColor;

  /// Ambient / hover glow behind the card.
  final bool glow;

  /// Run the border current.
  final bool animateBorder;

  /// Border thickness.
  final double borderWidth;

  /// Makes the card a button.
  final VoidCallback? onTap;

  /// Accessibility label for the button.
  final String? semanticsLabel;

  @override
  State<NeuralGlassCard> createState() => _NeuralGlassCardState();
}

class _NeuralGlassCardState extends State<NeuralGlassCard>
    with TickerProviderStateMixin {
  late final NeuralClock _clock = NeuralClock(this);
  late final AnimationController _emphasis = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  bool _hover = false;
  bool _focus = false;
  bool _pressed = false;
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotionOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(NeuralGlassCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    _clock.setRunning(widget.animateBorder && !_reduce);
  }

  void _updateEmphasis() {
    final target = _pressed
        ? 1.0
        : (_hover || _focus)
            ? 0.7
            : 0.0;
    if (_reduce) {
      _emphasis.value = target;
    } else {
      _emphasis.animateTo(target);
    }
  }

  @override
  void dispose() {
    _emphasis.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = NeuralPalette.of(
      context,
      accent: widget.color,
      secondary: widget.secondaryColor,
    );
    final radius = finiteOr(widget.borderRadius, 24).clamp(0.0, 400.0);
    final blur = finiteOr(widget.blur, 18).clamp(0.0, 80.0);
    final tint = widget.tint ??
        scheme.surface.withValues(alpha: palette.isDark ? 0.42 : 0.58);
    final interactive = widget.onTap != null;

    Widget glass = DecoratedBox(
      // Gradient only (no `color`): a color's alpha would dim the shader.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: palette.isDark ? 0.07 : 0.22),
              tint,
            ),
            tint,
            Color.alphaBlend(palette.accent.withValues(alpha: 0.06), tint),
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );
    if (blur > 0) {
      glass = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: glass,
      );
    }
    glass = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: glass,
    );

    Widget card = CustomPaint(
      painter: widget.glow
          ? _GlowPainter(
              emphasis: _emphasis,
              palette: palette,
              radius: radius,
            )
          : null,
      foregroundPainter: _BorderCurrentPainter(
        clock: _clock,
        emphasis: _emphasis,
        palette: palette,
        radius: radius,
        width: finiteOr(widget.borderWidth, 1.4).clamp(0.0, 8.0),
        animated: widget.animateBorder,
      ),
      child: glass,
    );

    card = AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: _reduce ? Duration.zero : const Duration(milliseconds: 120),
      child: RepaintBoundary(child: card),
    );

    if (!interactive) return card;
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) {
          _hover = v;
          _updateEmphasis();
        },
        onShowFocusHighlight: (v) {
          _focus = v;
          _updateEmphasis();
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTapDown: (_) {
            setState(() => _pressed = true);
            _updateEmphasis();
          },
          onTapUp: (_) {
            setState(() => _pressed = false);
            _updateEmphasis();
          },
          onTapCancel: () {
            setState(() => _pressed = false);
            _updateEmphasis();
          },
          onTap: widget.onTap,
          child: card,
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.emphasis,
    required this.palette,
    required this.radius,
  }) : super(repaint: emphasis);

  final Animation<double> emphasis;
  final NeuralPalette palette;
  final double radius;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final k = palette.glowIntensity;
    if (k <= 0) return;
    final e = emphasis.value;
    final rr = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(6),
      Radius.circular(radius),
    );
    _paint
      ..color = palette.accent.withValues(
        alpha: ((palette.isDark ? 0.16 : 0.12) + 0.26 * e) * k.clamp(0, 1.5),
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 + 10 * e);
    canvas.drawRRect(rr.shift(const Offset(0, 6)), _paint);
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.emphasis != emphasis ||
      old.palette != palette ||
      old.radius != radius;
}

class _BorderCurrentPainter extends CustomPainter {
  _BorderCurrentPainter({
    required this.clock,
    required this.emphasis,
    required this.palette,
    required this.radius,
    required this.width,
    required this.animated,
  }) : super(repaint: Listenable.merge([clock, emphasis]));

  final ValueListenable<double> clock;
  final Animation<double> emphasis;
  final NeuralPalette palette;
  final double radius;
  final double width;
  final bool animated;

  final Paint _base = Paint()..style = PaintingStyle.stroke;
  final Paint _current = Paint();
  Path? _ring;
  Size _ringSize = Size.zero;
  ui.Shader? _sweep;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite || width <= 0) return;
    final rect = (Offset.zero & size).deflate(width / 2);
    final r = Radius.circular(math.max(0, radius - width / 2));
    final rr = RRect.fromRectAndRadius(rect, r);
    final e = emphasis.value;

    _base
      ..strokeWidth = width
      ..color = palette.foreground
          .withValues(alpha: (palette.isDark ? 0.14 : 0.10) + 0.1 * e);
    canvas.drawRRect(rr, _base);

    // The current: a cached sweep shader rotated by the canvas inside a
    // cached ring clip, so a frame allocates nothing.
    if (_ring == null || _ringSize != size) {
      _ringSize = size;
      final outer =
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
      final inner = outer.deflate(width * 1.6);
      _ring = Path()
        ..fillType = PathFillType.evenOdd
        ..addRRect(outer)
        ..addRRect(inner);
    }
    final a = palette.accent;
    final b = palette.secondary;
    _sweep ??= ui.Gradient.sweep(
      Offset.zero,
      [
        a.withValues(alpha: 0),
        b.withValues(alpha: 0.6),
        a,
        a.withValues(alpha: 0),
        a.withValues(alpha: 0),
        b.withValues(alpha: 0.35),
        a.withValues(alpha: 0.55),
        a.withValues(alpha: 0),
      ],
      const [0, 0.16, 0.28, 0.3, 0.5, 0.66, 0.78, 0.8],
    );
    final angle = animated ? clock.value * 0.9 : -math.pi / 3;
    final reach = size.longestSide;
    canvas.save();
    canvas.clipPath(_ring!);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    _current
      ..shader = _sweep
      ..color = Color.fromRGBO(0, 0, 0, (0.75 + 0.25 * e).clamp(0.0, 1.0));
    canvas.drawCircle(Offset.zero, reach, _current);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BorderCurrentPainter old) =>
      old.clock != clock ||
      old.emphasis != emphasis ||
      old.palette != palette ||
      old.radius != radius ||
      old.width != width ||
      old.animated != animated;
}
