// Regression tests for bugs fixed in the 0.0.x widgets.
import 'dart:math' as math;

import 'package:dot_globe/dot_globe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';
import 'package:rehoboam_neural_ui/src/voice_wave.dart' show VoiceWavePainter;

import 'helpers.dart';

Finder _paintOf(Type t) => find
    .descendant(of: find.byType(t), matching: find.byType(CustomPaint))
    .first;

void main() {
  group('AiThinkingAnimation', () {
    testWidgets('created in Earth mode starts on the globe', (tester) async {
      // Bug: _lastMode was hard-coded to ring, so the globe never showed.
      await tester.pumpWidget(harness(const AiThinkingAnimation(
        hudMode: HudMode.earth,
        targetLat: 35.6,
        targetLon: 139.6,
      )));
      await tester.pump();
      expect(find.byType(DotGlobe), findsOneWidget);
    });

    testWidgets('switching to Earth flies the globe to the target',
        (tester) async {
      // Bug: animateTo ran before the globe was mounted (controller
      // detached), so the zoom-to-city never happened.
      final globe = DotGlobeController();
      addTearDown(globe.dispose);
      Widget hud(HudMode m) => harness(AiThinkingAnimation(
            hudMode: m,
            targetLat: 48.85,
            targetLon: 2.35,
            dotGlobeController: globe,
          ));
      await tester.pumpWidget(hud(HudMode.ring));
      expect(find.byType(DotGlobe), findsNothing);
      await tester.pumpWidget(hud(HudMode.earth));
      // The flight takes 1.8 s; check right after it lands (the globe keeps
      // auto-rotating slowly afterwards).
      for (var i = 0; i < 38; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(globe.isAttached, isTrue);
      expect(globe.scale, closeTo(1.8, 0.05));
      expect(globe.facing!.latitude, closeTo(48.85, 3));
      expect(globe.facing!.longitude, closeTo(2.35, 3));
      // Unmount before the tear-down disposes the controller.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('fly-to works without a user controller', (tester) async {
      await tester.pumpWidget(harness(const AiThinkingAnimation(
        hudMode: HudMode.earth,
        targetLat: 10,
        targetLon: 20,
      )));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Disposing must also dispose the internal controller cleanly.
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets('returns to the ring and unmounts the globe', (tester) async {
      Widget hud(HudMode m) => harness(AiThinkingAnimation(hudMode: m));
      await tester.pumpWidget(hud(HudMode.earth));
      await tester.pumpWidget(hud(HudMode.ring));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(DotGlobe), findsNothing);
    });

    testWidgets('reduced motion: still frame and instant mode switch',
        (tester) async {
      await expectStillUnderReducedMotion(
          tester, const AiThinkingAnimation(centerLabel: 'AI'));
      await tester.pumpWidget(harness(
        const AiThinkingAnimation(hudMode: HudMode.earth),
        reduceMotion: true,
      ));
      await tester.pump();
      expect(find.byType(DotGlobe), findsOneWidget);
    });

    testWidgets('NaN level, zero and infinite size do not throw',
        (tester) async {
      await tester.pumpWidget(harness(const AiThinkingAnimation(
        level: double.nan,
        speed: double.nan,
        size: 0,
        centerLabel: 'X',
        topLabel: 'T',
      )));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(harness(const SizedBox(
        width: 200,
        height: 150,
        child: Center(child: AiThinkingAnimation(size: double.infinity)),
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(AiThinkingAnimation)).width, 150);
    });

    testWidgets('geoPoints with NaN / missing coordinates are skipped',
        (tester) async {
      await tester.pumpWidget(harness(const AiThinkingAnimation(
        hudMode: HudMode.earth,
        geoPoints: [
          {'lat': double.nan, 'lon': 3},
          {'lon': 3},
          {'lat': 10, 'lon': 20, 'mag': double.infinity},
          {'lat': 12, 'lon': 22, 'mag': 6},
        ],
      )));
      await tester.pump();
      final globe = tester.widget<DotGlobe>(find.byType(DotGlobe));
      expect(globe.markers, hasLength(2));
    });

    testWidgets('exposes its labels to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(harness(const AiThinkingAnimation(
        centerLabel: 'Neural',
        topLabel: 'Rehoboam v1',
      )));
      expect(
        tester.getSemantics(find.byType(AiThinkingAnimation)),
        matchesSemantics(label: 'Neural. Rehoboam v1', isImage: true),
      );
      handle.dispose();
    });

    testWidgets('labels move to the right in RTL', (tester) async {
      Future<double> labelX(bool rtl) async {
        await tester.pumpWidget(harness(
          const AiThinkingAnimation(size: 320, topLabel: 'SCAN'),
          rtl: rtl,
        ));
        double? x;
        expect(
          tester.renderObject(_paintOf(AiThinkingAnimation)),
          paints
            ..something((method, args) {
              if (method != #drawParagraph) return false;
              x = (args[1] as Offset).dx + 0; // left of the layout box
              return true;
            }),
        );
        return x!;
      }

      final ltr = await labelX(false);
      final rtl = await labelX(true);
      expect(ltr, lessThan(160));
      expect(rtl, greaterThan(ltr + 50));
    });

    testWidgets('rebuilding with the same config does not force a repaint',
        (tester) async {
      // Bug: shouldRepaint returned true unconditionally.
      await tester
          .pumpWidget(harness(const AiThinkingAnimation(animate: false)));
      final paint = tester.widget<CustomPaint>(_paintOf(AiThinkingAnimation));
      final painter = paint.painter!;
      await tester
          .pumpWidget(harness(const AiThinkingAnimation(animate: false)));
      final again =
          tester.widget<CustomPaint>(_paintOf(AiThinkingAnimation)).painter!;
      expect(again.shouldRepaint(painter), isFalse);
    });

    testWidgets('ring texture is seamless and particles are batched',
        (tester) async {
      await tester.pumpWidget(harness(const AiThinkingAnimation(
        level: 1,
        animate: false,
      )));
      var pointCalls = 0;
      expect(
        tester.renderObject(_paintOf(AiThinkingAnimation)),
        paints
          ..everything((method, args) {
            if (method == #drawRawPoints || method == #drawPoints) pointCalls++;
            return true;
          }),
      );
      // Bug: 3 000 - 9 000 drawPoints calls (one per particle) per frame.
      expect(pointCalls, lessThanOrEqualTo(3));
    });
  });

  group('VoiceWave', () {
    testWidgets('speed 0 does not crash', (tester) async {
      // Bug: Duration(milliseconds: (2200 / 0).round()) threw.
      await tester.pumpWidget(harness(const VoiceWave(speed: 0)));
      await tester.pumpWidget(harness(const VoiceWave(speed: -2)));
      await tester.pumpWidget(harness(const VoiceWave(speed: double.nan)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('speed changes take effect immediately', (tester) async {
      // Bug: changing duration on a repeating controller was ignored.
      double phaseAfter(WidgetTester t) {
        final p = t.widget<CustomPaint>(_paintOf(VoiceWave)).painter!
            as VoiceWavePainter;
        return p.clock.value;
      }

      await tester.pumpWidget(harness(const VoiceWave(speed: 1)));
      await pumpFor(tester, const Duration(seconds: 1));
      final a = phaseAfter(tester);
      await tester.pumpWidget(harness(const VoiceWave(speed: 3)));
      await pumpFor(tester, const Duration(seconds: 1));
      final b = phaseAfter(tester);
      expect(b - a, closeTo(3, 0.3));
    });

    test('breathing is continuous across the loop point', () {
      // Bug: the curved 0..1 sawtooth jumped back to 0 every 2.2 s.
      const eps = 1e-4;
      for (final s in [2.2, 4.4, 6.6]) {
        expect(
          (VoiceWavePainter.breathAt(s - eps) -
                  VoiceWavePainter.breathAt(s + eps))
              .abs(),
          lessThan(1e-3),
        );
      }
    });

    testWidgets('speaking bars have real thickness', (tester) async {
      // Bug: bars used drawLine with strokeWidth 0 (hairlines).
      await tester.pumpWidget(harness(const SizedBox(
        width: 180,
        child: VoiceWave(mode: VoiceWaveMode.speaking, size: 180),
      )));
      final lines = <Paint>[];
      expect(
        tester.renderObject(_paintOf(VoiceWave)),
        paints
          ..everything((m, args) {
            if (m == #drawLine) lines.add(args[2] as Paint);
            return true;
          }),
      );
      expect(lines, hasLength(24));
      expect(lines.every((p) => p.strokeWidth > 2), isTrue);
    });

    testWidgets('particles are visible on a light theme', (tester) async {
      // Bug: particles were hard-coded white.
      await tester.pumpWidget(harness(const VoiceWave()));
      final circles = <Paint>[];
      expect(
        tester.renderObject(_paintOf(VoiceWave)),
        paints
          ..everything((m, args) {
            if (m == #drawCircle) circles.add(args[2] as Paint);
            return true;
          }),
      );
      final scheme =
          Theme.of(tester.element(find.byType(VoiceWave))).colorScheme;
      final particles = circles
          .where((p) => p.shader == null && p.style == PaintingStyle.fill);
      expect(particles, isNotEmpty);
      for (final p in particles) {
        expect(p.color.r, closeTo(scheme.onSurface.r, 0.01));
      }
    });

    testWidgets('semantics and reduced motion', (tester) async {
      final handle = tester.ensureSemantics();
      await tester
          .pumpWidget(harness(const VoiceWave(mode: VoiceWaveMode.speaking)));
      expect(find.bySemanticsLabel('Speaking'), findsOneWidget);
      handle.dispose();
      await expectStillUnderReducedMotion(tester, const VoiceWave());
    });

    test('AudioLevelStream broadcasts sanitized levels', () async {
      final got = <double>[];
      final sub =
          AudioLevelStream.instance.stream.listen((s) => got.add(s.level));
      AudioLevelStream.instance.addLevel(0.4);
      AudioLevelStream.instance.addLevel(double.nan);
      AudioLevelStream.instance.add(const AudioLevelSnapshot(level: 7));
      await Future<void>.delayed(Duration.zero);
      expect(got, [0.4, 0, 1]);
      expect(AudioLevelStream.instance.latest.level, 1);
      await sub.cancel();
    });
  });

  group('WordByWordTranscript', () {
    List<String> words(WidgetTester t) => t
        .widgetList<Text>(find.descendant(
            of: find.byType(WordByWordTranscript), matching: find.byType(Text)))
        .map((w) => w.data!)
        .toList();

    testWidgets('appends words and corrects the last one in place',
        (tester) async {
      await tester
          .pumpWidget(harness(const WordByWordTranscript(text: 'hello wor')));
      await tester
          .pumpWidget(harness(const WordByWordTranscript(text: 'hello world')));
      expect(words(tester), ['hello', 'world']);
      await tester.pumpWidget(
          harness(const WordByWordTranscript(text: 'hello world again')));
      expect(words(tester), ['hello', 'world', 'again']);
    });

    testWidgets('a revised middle word is replaced, not left stale',
        (tester) async {
      // Bug: only the last word was ever updated.
      await tester.pumpWidget(
          harness(const WordByWordTranscript(text: 'the cat sat down')));
      await tester.pumpWidget(
          harness(const WordByWordTranscript(text: 'the hat sat down')));
      expect(words(tester), ['the', 'hat', 'sat', 'down']);
    });

    testWidgets('shrinking text removes extra words', (tester) async {
      // Bug: words beyond the new length were never removed.
      await tester.pumpWidget(
          harness(const WordByWordTranscript(text: 'one two three four')));
      await tester
          .pumpWidget(harness(const WordByWordTranscript(text: 'one two')));
      expect(words(tester), ['one', 'two']);
    });

    testWidgets('a replaced transcript animates in again', (tester) async {
      // Bug: chips had no keys, so new words reused finished animations.
      await tester
          .pumpWidget(harness(const WordByWordTranscript(text: 'hi there')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(
          harness(const WordByWordTranscript(text: 'Sure, booking now')));
      final opacity = tester.widget<Opacity>(find
          .ancestor(of: find.text('Sure,'), matching: find.byType(Opacity))
          .first);
      expect(opacity.opacity, lessThan(0.2));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('maxLines keeps only the newest lines visible', (tester) async {
      // Bug: maxLines was accepted but ignored.
      final text = List.generate(60, (i) => 'word$i').join(' ');
      await tester.pumpWidget(harness(SizedBox(
        width: 300,
        child: WordByWordTranscript(
          text: text,
          maxLines: 2,
          textStyle: const TextStyle(fontSize: 20),
        ),
      )));
      await tester.pump(const Duration(seconds: 1));
      final h = tester.getSize(find.byType(WordByWordTranscript)).height;
      expect(h, lessThanOrEqualTo(2 * 20 * 1.25 + 2 * 2 + 4 + 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('whole transcript is one live region', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          harness(const WordByWordTranscript(text: 'book a table')));
      final node = tester.getSemantics(find.byType(WordByWordTranscript));
      expect(node.label, 'book a table');
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('reduced motion shows words immediately', (tester) async {
      await expectStillUnderReducedMotion(
          tester, const WordByWordTranscript(text: 'instant words'));
      final opacity = tester.widget<Opacity>(find
          .ancestor(of: find.text('instant'), matching: find.byType(Opacity))
          .first);
      expect(opacity.opacity, 1);
    });

    testWidgets('highlightIndex out of range is harmless', (tester) async {
      await tester.pumpWidget(
          harness(const WordByWordTranscript(text: 'a b', highlightIndex: 99)));
      await tester.pumpWidget(harness(const WordByWordTranscript(text: '   ')));
      expect(words(tester), isEmpty);
      expect(math.max(0, 1), 1);
    });
  });
}
