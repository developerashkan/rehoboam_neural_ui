import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';
import 'package:rehoboam_neural_ui/src/widgets/neural_heatmap.dart'
    show NeuralHeatmapPainter;
import 'package:rehoboam_neural_ui/src/widgets/neural_network_background.dart'
    show NeuralNetworkSim;
import 'package:rehoboam_neural_ui/src/widgets/neural_orb.dart'
    show NeuralOrbPainter, OrbParams;
import 'package:rehoboam_neural_ui/src/widgets/neural_sparkline.dart'
    show NeuralSparklinePainter;

import 'helpers.dart';

/// Every new widget with representative, slightly hostile inputs.
final Map<String, Widget> _gallery = {
  'orb': const NeuralOrb(state: NeuralOrbState.thinking, level: 0.6),
  'progress': const NeuralProgress(value: 0.4),
  'progress-indeterminate': const NeuralProgress(),
  'progress-linear':
      const SizedBox(width: 240, child: NeuralProgress.linear(value: 0.7)),
  'gauge': const NeuralGauge(value: 72, unit: '%', label: 'CPU'),
  'sparkline': const SizedBox(
      width: 260, child: NeuralSparkline(data: [3, 5, 4, 8, 6, 9, 7])),
  'network':
      const SizedBox(width: 300, height: 200, child: NeuralNetworkBackground()),
  'heatmap': SizedBox(
    width: 360,
    child: NeuralHeatmap(
      values: {DateTime(2026, 11, 1): 4, DateTime(2026, 11, 2): 9},
      endDate: DateTime(2026, 11, 10),
    ),
  ),
  'glass': const NeuralGlassCard(child: Text('Glass')),
  'scan': const NeuralScanRing(progress: 0.5),
  'avatar':
      const NeuralAvatar(name: 'Ada Lovelace', speaking: true, level: 0.5),
};

void main() {
  group('all new widgets', () {
    for (final e in _gallery.entries) {
      testWidgets('${e.key}: light, dark, RTL and dispose', (tester) async {
        for (final dark in [false, true]) {
          for (final rtl in [false, true]) {
            await tester.pumpWidget(harness(e.value, dark: dark, rtl: rtl));
            await pumpFor(tester, const Duration(milliseconds: 200));
            expect(tester.takeException(), isNull);
          }
        }
        // Disposing mid-animation must not leak tickers or call setState.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      });

      testWidgets('${e.key}: reduced motion stops all frames', (tester) async {
        await expectStillUnderReducedMotion(tester, e.value);
      });

      testWidgets('${e.key}: survives zero size', (tester) async {
        await tester.pumpWidget(harness(SizedBox(
          width: 0,
          height: 0,
          child: OverflowBox(maxWidth: 0, maxHeight: 0, child: e.value),
        )));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('NaN / infinite inputs are sanitized', (tester) async {
      await tester.pumpWidget(harness(Column(
        children: [
          const NeuralOrb(
              level: double.nan, size: double.nan, speed: double.nan),
          const NeuralProgress(value: double.nan, size: double.infinity),
          const NeuralGauge(value: double.nan, min: 5, max: 5),
          const NeuralGauge(value: double.infinity, min: 10, max: 0),
          const SizedBox(
            width: 200,
            child: NeuralSparkline(
                data: [double.nan, 1, double.infinity, 2, double.nan]),
          ),
          const NeuralScanRing(progress: double.nan, size: double.nan),
          const NeuralAvatar(level: double.nan, size: double.infinity),
        ].map((w) => Flexible(child: w)).toList(),
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });

  group('NeuralOrb', () {
    testWidgets('tap and button semantics', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(harness(NeuralOrb(onTap: () => taps++)));
      await tester.tap(find.byType(NeuralOrb));
      expect(taps, 1);
      expect(
        tester.getSemantics(find.byType(NeuralOrb)),
        matchesSemantics(
          label: 'AI assistant, idle',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('state changes ease instead of snapping', (tester) async {
      await tester.pumpWidget(harness(const NeuralOrb()));
      await pumpFor(tester, const Duration(milliseconds: 100));
      OrbParams params() => (tester
              .widget<CustomPaint>(find.descendant(
                  of: find.byType(NeuralOrb),
                  matching: find.byType(CustomPaint)))
              .painter! as NeuralOrbPainter)
          .params;
      expect(params().vortex, closeTo(0.15, 0.02));
      await tester
          .pumpWidget(harness(const NeuralOrb(state: NeuralOrbState.thinking)));
      await tester.pump(const Duration(milliseconds: 16));
      final mid = params().vortex;
      expect(mid, inExclusiveRange(0.15, 0.9));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(params().vortex, closeTo(1, 0.02));
    });

    testWidgets('reduced motion applies the new state at once', (tester) async {
      await tester.pumpWidget(harness(const NeuralOrb(), reduceMotion: true));
      await tester.pumpWidget(harness(
          const NeuralOrb(state: NeuralOrbState.thinking),
          reduceMotion: true));
      final p = tester
          .widget<CustomPaint>(find.descendant(
              of: find.byType(NeuralOrb), matching: find.byType(CustomPaint)))
          .painter! as NeuralOrbPainter;
      expect(p.params.vortex, 1);
    });

    test('surface is closed (seamless at 0 / 2π)', () {
      for (final s in [0.0, 1.7, 123.4]) {
        expect(
            NeuralOrbPainter.surface(0, s, 0.1, 0.5),
            closeTo(
                NeuralOrbPainter.surface(2 * 3.141592653589793, s, 0.1, 0.5),
                1e-9));
      }
    });
  });

  group('NeuralProgress', () {
    testWidgets('exposes percentage semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(harness(const NeuralProgress(value: 0.426)));
      final node = tester.getSemantics(find.byType(NeuralProgress));
      expect(node.label, 'Loading');
      expect(node.value, '43%');
      await tester.pumpWidget(harness(const NeuralProgress()));
      expect(tester.getSemantics(find.byType(NeuralProgress)).value, isEmpty);
      handle.dispose();
    });

    testWidgets('fill animates toward a new value', (tester) async {
      double sweep() {
        double? s;
        expect(
          tester.renderObject(find.descendant(
              of: find.byType(NeuralProgress),
              matching: find.byType(CustomPaint))),
          paints
            ..something((m, args) {
              if (m != #drawArc) return false;
              s = args[2] as double;
              return (args[4] as Paint).maskFilter == null;
            }),
        );
        return s!;
      }

      await tester.pumpWidget(harness(const NeuralProgress(
          value: 0.2, duration: Duration(milliseconds: 400))));
      expect(sweep(), closeTo(0.2 * 2 * 3.14159, 0.01));
      await tester.pumpWidget(harness(const NeuralProgress(
          value: 0.8, duration: Duration(milliseconds: 400))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sweep(), inExclusiveRange(0.2 * 6.283, 0.8 * 6.283));
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(sweep(), closeTo(0.8 * 2 * 3.14159, 0.01));
    });

    testWidgets('circular fill runs counter-clockwise in RTL', (tester) async {
      double sweepFor(bool rtl) {
        double? s;
        expect(
          tester.renderObject(find.descendant(
              of: find.byType(NeuralProgress),
              matching: find.byType(CustomPaint))),
          paints
            ..something((m, args) {
              if (m != #drawArc) return false;
              s = args[2] as double;
              return true;
            }),
        );
        return s!;
      }

      await tester.pumpWidget(harness(const NeuralProgress(value: 0.5)));
      expect(sweepFor(false), greaterThan(0));
      await tester
          .pumpWidget(harness(const NeuralProgress(value: 0.5), rtl: true));
      expect(sweepFor(true), lessThan(0));
    });

    testWidgets('linear fill starts at the right in RTL', (tester) async {
      Rect fillRect(bool rtl) {
        Rect? r;
        expect(
          tester.renderObject(find.descendant(
              of: find.byType(NeuralProgress),
              matching: find.byType(CustomPaint))),
          paints
            ..something((m, args) {
              if (m != #drawRRect) return false;
              final p = args[1] as Paint;
              if (p.shader == null) return false;
              r = (args[0] as RRect).outerRect;
              return true;
            }),
        );
        return r!;
      }

      const bar =
          SizedBox(width: 200, child: NeuralProgress.linear(value: 0.25));
      await tester.pumpWidget(harness(bar));
      expect(fillRect(false).left, closeTo(0, 0.01));
      await tester.pumpWidget(harness(bar, rtl: true));
      expect(fillRect(true).right, closeTo(200, 0.01));
      expect(fillRect(true).width, closeTo(50, 0.01));
    });
  });

  group('NeuralGauge', () {
    testWidgets('clamps, formats and animates the readout', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(harness(
          const NeuralGauge(value: 140, max: 100, unit: '%', label: 'CPU')));
      expect(find.textContaining('100'), findsOneWidget);
      final node = tester.getSemantics(find.byType(NeuralGauge));
      expect(node.label, 'CPU');
      expect(node.value, '100%');

      await tester.pumpWidget(harness(
          const NeuralGauge(value: 20, max: 100, unit: '%', label: 'CPU')));
      await tester.pump(const Duration(milliseconds: 300));
      final mid = int.parse(RegExp(r'\d+')
          .firstMatch(tester
              .widget<Text>(find.byType(Text).first)
              .textSpan!
              .toPlainText())!
          .group(0)!);
      expect(mid, inExclusiveRange(20, 100));
      await tester.pumpAndSettle();
      expect(find.textContaining('20'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('custom formatter and empty range', (tester) async {
      await tester.pumpWidget(harness(NeuralGauge(
        value: 3,
        min: 3,
        max: 3,
        valueFormatter: (v) => 'v=$v',
      )));
      expect(find.textContaining('v=3.0'), findsOneWidget);
    });

    testWidgets('thresholds recolor the arc', (tester) async {
      await tester.pumpWidget(harness(const NeuralGauge(
        value: 95,
        thresholds: [NeuralGaugeThreshold(80, Color(0xFFFF0000))],
        duration: Duration.zero,
      )));
      final arcs = <Paint>[];
      expect(
        tester.renderObject(find.descendant(
            of: find.byType(NeuralGauge), matching: find.byType(CustomPaint))),
        paints
          ..everything((m, args) {
            if (m == #drawArc) arcs.add(args[4] as Paint);
            return true;
          }),
      );
      expect(arcs.last.color, const Color(0xFFFF0000));
    });
  });

  group('NeuralSparkline', () {
    test('monotone tangents never overshoot', () {
      final xs = <double>[0, 1, 2, 3, 4];
      final ys = <double>[0, 10, 10, 0, 5];
      final m = NeuralSparklinePainter.monotoneTangents(xs, ys);
      expect(m[1], 0, reason: 'flat neighbour -> zero slope at a plateau');
      expect(m[2], 0);
      // Sample every Hermite segment: values stay inside the data range.
      for (var i = 0; i < 4; i++) {
        for (var k = 1; k < 10; k++) {
          final t = k / 10;
          final h00 = 2 * t * t * t - 3 * t * t + 1;
          final h10 = t * t * t - 2 * t * t + t;
          final h01 = -2 * t * t * t + 3 * t * t;
          final h11 = t * t * t - t * t;
          final y = h00 * ys[i] + h10 * m[i] + h01 * ys[i + 1] + h11 * m[i + 1];
          expect(y, inInclusiveRange(-1e-9, 10 + 1e-9));
        }
      }
    });

    testWidgets('scrubbing reports indices and mirrors in RTL', (tester) async {
      final got = <int?>[];
      Widget chart() => SizedBox(
            width: 300,
            child: NeuralSparkline(
              data: const [1, 2, 3, 4, 5],
              onScrub: got.add,
            ),
          );
      await tester.pumpWidget(harness(chart()));
      await pumpFor(tester, const Duration(seconds: 1));
      final box = tester.getRect(find.byType(NeuralSparkline));
      final gesture =
          await tester.startGesture(box.centerLeft + const Offset(2, 0));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.moveTo(box.centerRight - const Offset(2, 0));
      await tester.pump();
      expect(find.text('5.0'), findsOneWidget, reason: 'tooltip shows value');
      await gesture.up();
      await tester.pump();
      expect(got.first, 0);
      expect(got.contains(4), isTrue);
      expect(got.last, isNull);

      got.clear();
      await tester.pumpWidget(harness(chart(), rtl: true));
      await tester.tapAt(box.centerLeft + const Offset(2, 0));
      await tester.pump();
      expect(got.first, 4, reason: 'left edge is the newest point in RTL');
    });

    testWidgets('morphs when data changes, skips identical rebuilds',
        (tester) async {
      await tester.pumpWidget(harness(
          const SizedBox(width: 200, child: NeuralSparkline(data: [1, 2, 3]))));
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.pumpWidget(harness(
          const SizedBox(width: 200, child: NeuralSparkline(data: [1, 2, 3]))));
      await tester.pump(const Duration(milliseconds: 16));
      // Same content: no morph restarted (only the latest-dot pulse ticks).
      final anim = (tester
              .widget<CustomPaint>(find.descendant(
                  of: find.byType(NeuralSparkline),
                  matching: find.byType(CustomPaint)))
              .painter! as NeuralSparklinePainter)
          .animation;
      expect(anim.value, 1);
      await tester.pumpWidget(harness(const SizedBox(
          width: 200, child: NeuralSparkline(data: [5, 1, 4, 2, 8]))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(anim.value, lessThan(1));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(anim.value, 1);
    });

    testWidgets('semantics summarise the series; empty data is safe',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(harness(const SizedBox(
          width: 200,
          child: NeuralSparkline(data: [2, 9, 4], semanticsLabel: 'Revenue'))));
      final node = tester.getSemantics(find.byType(NeuralSparkline));
      expect(node.label, 'Revenue');
      expect(node.value, 'Latest 4.0, min 2.0, max 9.0');
      await tester.pumpWidget(harness(
          const SizedBox(width: 200, child: NeuralSparkline(data: []))));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
          tester.getSemantics(find.byType(NeuralSparkline)).value, 'No data');
      handle.dispose();
    });
  });

  group('NeuralNetworkBackground', () {
    test('simulation is deterministic and stays in bounds', () {
      final a = NeuralNetworkSim(200, 3)..resize(const Size(400, 300), 1, 140);
      final b = NeuralNetworkSim(200, 3)..resize(const Size(400, 300), 1, 140);
      expect(a.count, 12);
      for (var i = 0; i < 600; i++) {
        a.step(1 / 60, 120, interactive: true);
        b.step(1 / 60, 120, interactive: true);
      }
      for (var i = 0; i < a.count; i++) {
        expect(a.x[i], b.x[i]);
        expect(a.x[i], inInclusiveRange(0, 400));
        expect(a.y[i], inInclusiveRange(0, 300));
      }
      final c = NeuralNetworkSim(200, 4)..resize(const Size(400, 300), 1, 140);
      expect(c.x[0], isNot(a.x[0]));
    });

    test('node count follows area, capped', () {
      final s = NeuralNetworkSim(240, 1)
        ..resize(const Size(2000, 2000), 1, 140);
      expect(s.count, 140);
      s.resize(const Size(100, 100), 1, 140);
      expect(s.count, 6);
    });

    test('pointer attracts nearby nodes', () {
      final s = NeuralNetworkSim(50, 9)..resize(const Size(300, 300), 5, 50);
      s.pointer = const Offset(150, 150);
      double meanDist() {
        var d = 0.0;
        for (var i = 0; i < s.count; i++) {
          d += (Offset(s.x[i], s.y[i]) - s.pointer!).distance;
        }
        return d / s.count;
      }

      final before = meanDist();
      for (var i = 0; i < 300; i++) {
        s.step(1 / 60, 120, interactive: true);
      }
      expect(meanDist(), lessThan(before));
    });

    testWidgets('child stays interactive and is the only semantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(harness(SizedBox(
        width: 300,
        height: 200,
        child: NeuralNetworkBackground(
          child: Center(
            child: TextButton(onPressed: () => taps++, child: const Text('Go')),
          ),
        ),
      )));
      await tester.tap(find.text('Go'));
      expect(taps, 1);
      expect(find.bySemanticsLabel('Go'), findsOneWidget);
      handle.dispose();
    });
  });

  group('NeuralHeatmap', () {
    test('dayKey ignores time of day and offsets', () {
      expect(NeuralHeatmap.dayKey(DateTime(2026, 3, 29, 23, 59)),
          NeuralHeatmap.dayKey(DateTime(2026, 3, 29, 0, 1)));
      expect(NeuralHeatmap.dayKey(DateTime.utc(2026, 3, 29, 12)), 20260329);
      expect(NeuralHeatmapPainter.level(0, 10), 0);
      expect(NeuralHeatmapPainter.level(10, 10), 4);
      expect(NeuralHeatmapPainter.level(double.nan, 10), 0);
      expect(NeuralHeatmapPainter.level(1, 0), 0);
    });

    testWidgets('taps map to consecutive calendar days across DST',
        (tester) async {
      final tapped = <DateTime>[];
      final end = DateTime(2026, 11, 7); // Saturday, after the EU/US DST end
      await tester.pumpWidget(harness(SizedBox(
        width: 420,
        child: NeuralHeatmap(
          values: {
            DateTime(2026, 10, 25, 23): 2, // same day twice -> summed
            DateTime(2026, 10, 25, 1): 3,
          },
          endDate: end,
          weeks: 10,
          cellSize: 20,
          cellSpacing: 4,
          showWeekdayLabels: false,
          showMonthLabels: false,
          onCellTap: (d, v) => tapped.add(d),
        ),
      )));
      await tester.pumpAndSettle();
      final grid = tester.getTopLeft(find.byType(CustomPaint).last);
      for (var col = 0; col < 10; col++) {
        for (var row = 0; row < 7; row++) {
          await tester.tapAt(grid + Offset(col * 24 + 10, row * 24 + 10));
        }
      }
      expect(tapped.last, end);
      for (var i = 1; i < tapped.length; i++) {
        final prev = tapped[i - 1];
        final next = DateTime(prev.year, prev.month, prev.day + 1);
        expect(NeuralHeatmap.dayKey(tapped[i]), NeuralHeatmap.dayKey(next),
            reason: 'day $i');
        expect(tapped[i].hour, 0);
      }
      expect(tapped.length, 70, reason: 'Saturday ends an en_US week');
    });

    testWidgets('summed values reach the callback and semantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      double? value;
      await tester.pumpWidget(harness(SizedBox(
        width: 420,
        child: NeuralHeatmap(
          values: {
            DateTime(2026, 11, 2, 23): 2,
            DateTime(2026, 11, 2, 1): 3,
            DateTime(2026, 11, 3): double.nan,
          },
          endDate: DateTime(2026, 11, 8), // Sunday
          weeks: 2,
          cellSize: 20,
          cellSpacing: 4,
          showWeekdayLabels: false,
          showMonthLabels: false,
          onCellTap: (d, v) => value = v,
        ),
      )));
      await tester.pumpAndSettle();
      final grid = tester.getTopLeft(find.byType(CustomPaint).last);
      // en_US weeks start on Sunday: column 0 is 1-7 Nov, Mon 2 Nov is row 1.
      await tester.tapAt(grid + const Offset(10, 24 + 10));
      expect(value, 5);
      final node = tester.getSemantics(find.byType(NeuralHeatmap));
      expect(node.value, startsWith('1 active days, total 5'));
      handle.dispose();
    });

    testWidgets('grid is mirrored in RTL', (tester) async {
      DateTime? day;
      final w = SizedBox(
        width: 420,
        child: NeuralHeatmap(
          values: const {},
          endDate: DateTime(2026, 11, 8),
          weeks: 4,
          cellSize: 20,
          cellSpacing: 4,
          showWeekdayLabels: false,
          showMonthLabels: false,
          onCellTap: (d, v) => day = d,
        ),
      );
      await tester.pumpWidget(harness(w, rtl: true));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(CustomPaint).last);
      // Sunday 8 Nov starts the newest (Sunday-first) week: row 0.
      await tester.tapAt(rect.topLeft + const Offset(10, 10));
      expect(day, DateTime(2026, 11, 8), reason: 'newest week is on the left');
    });
  });

  group('NeuralGlassCard', () {
    testWidgets('is a keyboard-activatable button', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(harness(NeuralGlassCard(
        onTap: () => taps++,
        semanticsLabel: 'Open report',
        child: const Text('Report'),
      )));
      await tester.tap(find.text('Report'));
      expect(taps, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 2);
      expect(
        tester.getSemantics(find.byType(NeuralGlassCard)),
        matchesSemantics(
          label: 'Open report\nReport',
          isButton: true,
          isFocusable: true,
          isFocused: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('blur 0 skips the backdrop filter', (tester) async {
      await tester.pumpWidget(
          harness(const NeuralGlassCard(blur: 0, child: Text('x'))));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(harness(const NeuralGlassCard(child: Text('x'))));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('NeuralScanRing', () {
    testWidgets('onResolved fires once after the success animation',
        (tester) async {
      final handle = tester.ensureSemantics();
      final resolved = <NeuralScanStatus>[];
      Widget ring(NeuralScanStatus s) => harness(NeuralScanRing(
            status: s,
            progress: 0.6,
            onResolved: resolved.add,
            child: const Icon(Icons.fingerprint),
          ));
      await tester.pumpWidget(ring(NeuralScanStatus.scanning));
      var node = tester.getSemantics(find.byType(NeuralScanRing));
      expect(node.label, 'Scanning');
      expect(node.value, '60%');
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      await tester.pumpWidget(ring(NeuralScanStatus.success));
      expect(resolved, isEmpty);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(resolved, [NeuralScanStatus.success]);
      node = tester.getSemantics(find.byType(NeuralScanRing));
      expect(node.label, 'Verified');
      await pumpFor(tester, const Duration(seconds: 1));
      expect(resolved, hasLength(1));
      handle.dispose();
    });

    testWidgets('failure shakes; reduced motion still resolves',
        (tester) async {
      final resolved = <NeuralScanStatus>[];
      await tester
          .pumpWidget(harness(NeuralScanRing(onResolved: resolved.add)));
      await tester.pumpWidget(harness(NeuralScanRing(
          status: NeuralScanStatus.failure, onResolved: resolved.add)));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(Transform), findsWidgets);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(resolved, [NeuralScanStatus.failure]);

      resolved.clear();
      await tester.pumpWidget(harness(NeuralScanRing(onResolved: resolved.add),
          reduceMotion: true));
      await tester.pumpWidget(harness(
          NeuralScanRing(
              status: NeuralScanStatus.success, onResolved: resolved.add),
          reduceMotion: true));
      await tester.pump();
      expect(resolved, [NeuralScanStatus.success]);
    });

    testWidgets('created resolved does not call back during build',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(harness(NeuralScanRing(
          status: NeuralScanStatus.success, onResolved: (_) => calls++)));
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('NeuralAvatar', () {
    test('initials are grapheme-aware', () {
      expect(NeuralAvatar.initialsOf('ada lovelace'), 'AL');
      expect(NeuralAvatar.initialsOf('  Grace   Brewster  Hopper '), 'GH');
      expect(NeuralAvatar.initialsOf('Plato'), 'P');
      expect(NeuralAvatar.initialsOf(''), '');
      expect(NeuralAvatar.initialsOf('👩🏽‍🚀 Nova'), '👩🏽‍🚀N');
      expect(NeuralAvatar.initialsOf('آرش کمانگیر'), 'آک');
    });

    testWidgets('semantics and RTL badge position', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(harness(const NeuralAvatar(
          name: 'Ada', presence: NeuralPresence.busy, speaking: true)));
      expect(find.bySemanticsLabel('Ada, busy, speaking'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      handle.dispose();

      double badgeX(bool rtl) {
        final badge = find.descendant(
            of: find.byType(NeuralAvatar),
            matching: find.byWidgetPredicate((w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).shape == BoxShape.circle));
        return tester.getCenter(badge).dx -
            tester.getCenter(find.byType(NeuralAvatar)).dx;
      }

      await tester.pumpWidget(harness(const NeuralAvatar(name: 'Ada')));
      expect(badgeX(false), greaterThan(0));
      await tester
          .pumpWidget(harness(const NeuralAvatar(name: 'Ada'), rtl: true));
      expect(badgeX(true), lessThan(0));
    });

    testWidgets('broken image falls back to initials', (tester) async {
      await tester.pumpWidget(harness(NeuralAvatar(
        name: 'Ada Lovelace',
        image: MemoryImage(Uint8List.fromList(const [0, 1, 2, 3])),
      )));
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.text('AL'), findsOneWidget);
    });

    testWidgets('offline avatar does not animate', (tester) async {
      await tester.pumpWidget(
          harness(const NeuralAvatar(presence: NeuralPresence.offline)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
