import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';

/// A glowing activity heatmap (contribution calendar): one column per week,
/// one cell per day, brightest where activity peaks.
///
/// * Dates are bucketed by calendar day (time of day and time zone offsets
///   are ignored), so daylight-saving changes never shift or duplicate
///   cells.
/// * Cells size themselves to the available width unless [cellSize] is set.
/// * Weeks start on the locale's first day (`MaterialLocalizations`) and the
///   grid flows with the reading direction (newest week at the end).
/// * Tap a cell to select it; [onCellTap] receives the day and its value.
class NeuralHeatmap extends StatefulWidget {
  /// Creates a heatmap.
  const NeuralHeatmap({
    super.key,
    required this.values,
    this.endDate,
    this.weeks = 20,
    this.cellSize,
    this.cellSpacing = 3,
    this.maxValue,
    this.color,
    this.emptyColor,
    this.onCellTap,
    this.showWeekdayLabels = true,
    this.showMonthLabels = true,
    this.monthLabelBuilder,
    this.duration = const Duration(milliseconds: 900),
    this.semanticsLabel,
  });

  /// Activity per day. Keys are bucketed by calendar day; duplicate days
  /// are summed. Non-finite and negative values count as zero.
  final Map<DateTime, double> values;

  /// Last day shown. Defaults to today.
  final DateTime? endDate;

  /// Number of week columns.
  final int weeks;

  /// Fixed cell side. Defaults to fitting the width.
  final double? cellSize;

  /// Gap between cells.
  final double cellSpacing;

  /// Value of the brightest cell. Defaults to the data maximum.
  final double? maxValue;

  /// Hot color. Defaults to the theme accent.
  final Color? color;

  /// Empty-cell color. Defaults to the theme track.
  final Color? emptyColor;

  /// Called with the tapped day (local midnight) and its value.
  final void Function(DateTime day, double value)? onCellTap;

  /// Show narrow weekday names down the side.
  final bool showWeekdayLabels;

  /// Show month names along the top.
  final bool showMonthLabels;

  /// Month caption. Defaults to English three-letter names.
  final String Function(int month)? monthLabelBuilder;

  /// Reveal animation length.
  final Duration duration;

  /// Accessibility label. Defaults to "Activity".
  final String? semanticsLabel;

  /// Calendar-day key for [d] (independent of time and offset).
  static int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  @override
  State<NeuralHeatmap> createState() => _NeuralHeatmapState();
}

class _NeuralHeatmapState extends State<NeuralHeatmap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: widget.duration);
  DateTime? _selected;
  Map<int, double> _byDay = const {};
  double _max = 1;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _index();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reveal.status == AnimationStatus.dismissed) {
      if (reduceMotionOf(context) || widget.duration == Duration.zero) {
        _reveal.value = 1;
      } else {
        _reveal.forward();
      }
    }
  }

  @override
  void didUpdateWidget(NeuralHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.values, widget.values) ||
        oldWidget.maxValue != widget.maxValue) {
      _index();
    }
  }

  void _index() {
    final m = <int, double>{};
    widget.values.forEach((k, v) {
      final value = v.isFinite && v > 0 ? v : 0.0;
      final key = NeuralHeatmap.dayKey(k);
      m[key] = (m[key] ?? 0) + value;
    });
    _byDay = m;
    final given = widget.maxValue;
    _max = given != null && given.isFinite && given > 0
        ? given
        : (m.values.isEmpty ? 1 : math.max(1e-9, m.values.reduce(math.max)));
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  /// Calendar arithmetic in UTC, then back to local midnight: immune to DST.
  static DateTime _addDays(DateTime d, int days) {
    final u = DateTime.utc(d.year, d.month, d.day + days);
    return DateTime(u.year, u.month, u.day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = NeuralPalette.of(
      context,
      accent: widget.color,
      track: widget.emptyColor,
    );
    final loc =
        Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
    final firstDow = loc?.firstDayOfWeekIndex ?? 1; // 0 = Sunday
    final narrow =
        loc?.narrowWeekdays ?? const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final now = widget.endDate ?? DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final weeks = widget.weeks.clamp(1, 260);
    // Column of `end`: its weekday row relative to the locale's first day.
    final endRow = (end.weekday % 7 - firstDow) % 7; // weekday%7: Sun=0
    final start = _addDays(end, -(endRow + (weeks - 1) * 7));
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: palette.foreground.withValues(alpha: 0.55),
      fontSize: 10,
    );
    final spacing = finiteOr(widget.cellSpacing, 3).clamp(0.0, 24.0);
    final monthName = widget.monthLabelBuilder ?? (m) => _months[m - 1];

    var activeDays = 0;
    var total = 0.0;
    DateTime? best;
    var bestValue = 0.0;
    for (var c = 0; c < weeks * 7; c++) {
      final d = _addDays(start, c);
      if (d.isAfter(end)) break;
      final v = _byDay[NeuralHeatmap.dayKey(d)] ?? 0;
      if (v > 0) activeDays++;
      total += v;
      if (v > bestValue) {
        bestValue = v;
        best = d;
      }
    }

    return Semantics(
      label: widget.semanticsLabel ?? 'Activity',
      value: best == null
          ? 'No activity'
          : '$activeDays active days, total ${_fmt(total)}, '
              'peak ${_fmt(bestValue)} on '
              '${loc?.formatMediumDate(best) ?? best.toIso8601String().split('T').first}',
      child: LayoutBuilder(
        builder: (context, c) {
          final sideLabel = widget.showWeekdayLabels ? 18.0 : 0.0;
          final topLabel = widget.showMonthLabels ? 16.0 : 0.0;
          final available =
              (c.maxWidth.isFinite ? c.maxWidth : 600) - sideLabel;
          final fitted = (available - spacing * (weeks - 1)) / weeks;
          final cell = finiteOr(widget.cellSize ?? fitted, 12).clamp(4.0, 64.0);
          final gridW = cell * weeks + spacing * (weeks - 1);
          final gridH = cell * 7 + spacing * 6;

          Widget grid = SizedBox(
            width: gridW,
            height: gridH,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: NeuralHeatmapPainter(
                  reveal: _reveal,
                  start: start,
                  end: end,
                  weeks: weeks,
                  cell: cell,
                  spacing: spacing,
                  byDay: _byDay,
                  max: _max,
                  palette: palette,
                  selected: _selected,
                ),
              ),
            ),
          );
          grid = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final p = d.localPosition;
              final col = (p.dx / (cell + spacing)).floor();
              final row = (p.dy / (cell + spacing)).floor();
              if (col < 0 || col >= weeks || row < 0 || row > 6) return;
              final day = _addDays(start, col * 7 + row);
              if (day.isAfter(end)) return;
              setState(() => _selected = day);
              widget.onCellTap
                  ?.call(day, _byDay[NeuralHeatmap.dayKey(day)] ?? 0);
            },
            child: grid,
          );

          final months = <Widget>[];
          if (widget.showMonthLabels) {
            // A month is labelled on the column holding its 1st; the
            // partial first column gets a label only if there is room.
            final firsts = <int, int>{}; // column -> month
            for (var w = 0; w < weeks; w++) {
              for (var r = 0; r < 7; r++) {
                final d = _addDays(start, w * 7 + r);
                if (d.day == 1 && !d.isAfter(end)) firsts[w] = d.month;
              }
            }
            if (!firsts.containsKey(0) &&
                (firsts.keys.isEmpty || firsts.keys.first >= 3)) {
              firsts[0] = start.month;
            }
            final minGap = 28 / (cell + spacing); // columns per label
            var lastCol = -1000.0;
            for (final w in (firsts.keys.toList()..sort())) {
              if (w - lastCol < minGap) continue;
              lastCol = w.toDouble();
              months.add(PositionedDirectional(
                start: sideLabel + w * (cell + spacing),
                top: 0,
                child: Text(monthName(firsts[w]!), style: labelStyle),
              ));
            }
          }

          final weekdays = <Widget>[];
          if (widget.showWeekdayLabels) {
            for (var r = 0; r < 7; r += 2) {
              weekdays.add(PositionedDirectional(
                start: 0,
                top: topLabel + r * (cell + spacing) + (cell - 12) / 2,
                child: SizedBox(
                  width: sideLabel - 4,
                  child: Text(
                    narrow[(firstDow + r) % 7],
                    style: labelStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
              ));
            }
          }

          return ExcludeSemantics(
            child: SizedBox(
              width: sideLabel + gridW,
              height: topLabel + gridH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ...months,
                  ...weekdays,
                  PositionedDirectional(
                    start: sideLabel,
                    top: topLabel,
                    // The grid mirrors itself in RTL (newest week at the
                    // reading end) via Directionality-aware painting.
                    child: Directionality.of(context) == TextDirection.rtl
                        ? Transform.flip(flipX: true, child: grid)
                        : grid,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

/// Paints [NeuralHeatmap]'s grid.
class NeuralHeatmapPainter extends CustomPainter {
  /// Creates the painter.
  NeuralHeatmapPainter({
    required this.reveal,
    required this.start,
    required this.end,
    required this.weeks,
    required this.cell,
    required this.spacing,
    required this.byDay,
    required this.max,
    required this.palette,
    this.selected,
  }) : super(repaint: reveal);

  /// Reveal progress.
  final Animation<double> reveal;

  /// First day (top of the first column).
  final DateTime start;

  /// Last day shown.
  final DateTime end;

  /// Columns.
  final int weeks;

  /// Cell side.
  final double cell;

  /// Gap.
  final double spacing;

  /// Values by [NeuralHeatmap.dayKey].
  final Map<int, double> byDay;

  /// Brightest value.
  final double max;

  /// Colors.
  final NeuralPalette palette;

  /// Highlighted day.
  final DateTime? selected;

  final Paint _paint = Paint();
  final Paint _glow = Paint();
  // Day keys per cell (-1 = after [end]); computed once per painter, not
  // per animation frame.
  late final List<int> _keys = [
    for (var i = 0; i < weeks * 7; i++)
      () {
        final u = DateTime.utc(start.year, start.month, start.day + i);
        final day = DateTime(u.year, u.month, u.day);
        return day.isAfter(end) ? -1 : NeuralHeatmap.dayKey(day);
      }(),
  ];
  final Paint _ring = Paint()..style = PaintingStyle.stroke;

  /// Intensity level `0..4` for [v] (GitHub-style quantization).
  static int level(double v, double max) {
    if (!(v > 0) || !(max > 0)) return 0;
    final f = (v / max).clamp(0.0, 1.0);
    return 1 + (f * 3.999).floor().clamp(0, 3);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final t = reveal.value;
    final radius = Radius.circular(cell * 0.28);
    final glowK = palette.glowIntensity;
    final selKey = selected == null ? null : NeuralHeatmap.dayKey(selected!);
    for (var col = 0; col < weeks; col++) {
      for (var row = 0; row < 7; row++) {
        final key = _keys[col * 7 + row];
        if (key < 0) continue;
        // Diagonal wave reveal.
        final order = (col + row) / (weeks + 6);
        final appear = ((t * 1.4 - order) / 0.4).clamp(0.0, 1.0);
        if (appear <= 0) continue;
        final v = byDay[key] ?? 0;
        final lv = level(v, max);
        final rect = Rect.fromLTWH(
          col * (cell + spacing),
          row * (cell + spacing),
          cell,
          cell,
        );
        final scaled = Rect.fromCenter(
          center: rect.center,
          width: cell * (0.5 + 0.5 * appear),
          height: cell * (0.5 + 0.5 * appear),
        );
        final rr = RRect.fromRectAndRadius(scaled, radius);
        if (lv >= 4 && glowK > 0) {
          _glow
            ..color = palette.accent
                .withValues(alpha: (0.55 * glowK * appear).clamp(0, 1))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.35);
          canvas.drawRRect(rr, _glow);
        }
        final strength = const [0.0, 0.28, 0.5, 0.75, 1.0][lv];
        _paint.color = lv == 0
            ? palette.track
            : Color.lerp(palette.track, palette.accent, strength)!;
        _paint.color = _paint.color.withValues(alpha: _paint.color.a * appear);
        canvas.drawRRect(rr, _paint);
        if (key == selKey) {
          _ring
            ..strokeWidth = math.max(1.5, cell * 0.12)
            ..color = palette.foreground;
          canvas.drawRRect(rr.inflate(_ring.strokeWidth), _ring);
        }
      }
    }
  }

  @override
  bool shouldRepaint(NeuralHeatmapPainter old) =>
      old.reveal != reveal ||
      old.start != start ||
      old.end != end ||
      old.weeks != weeks ||
      old.cell != cell ||
      old.spacing != spacing ||
      !identical(old.byDay, byDay) ||
      old.max != max ||
      old.palette != palette ||
      old.selected != selected;
}
