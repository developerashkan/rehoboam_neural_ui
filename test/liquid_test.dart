import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';
import 'package:rehoboam_neural_ui/src/liquid/liquid_orb.dart'
    show LiquidOrbPainter, LiquidOrbMotion;

import 'helpers.dart';

Future<ui.Image> _render(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
}

Future<List<int>> _pixel(
    WidgetTester tester, ui.Image img, int x, int y) async {
  final data = (await tester.runAsync(() => img.toByteData()))!;
  final i = (y * img.width + x) * 4;
  return [for (var k = 0; k < 4; k++) data.getUint8(i + k)];
}

void main() {
  testWidgets('every shader compiles and loads', (tester) async {
    await tester.runAsync(NeuralShaders.precache);
    for (final s in NeuralShader.values) {
      expect(NeuralShaders.cached(s), isNotNull,
          reason: '${s.fileName} failed');
      expect(NeuralShaders.failed(s), isFalse);
    }
  });

  testWidgets('liquid orb renders through the shader', (tester) async {
    await tester.runAsync(NeuralShaders.precache);
    final key = GlobalKey();
    await tester.pumpWidget(harness(RepaintBoundary(
      key: key,
      child: const NeuralLiquidOrb(size: 200, animate: false),
    )));
    await tester.pump();
    final painter = tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(NeuralLiquidOrb),
            matching: find.byType(CustomPaint)))
        .painter! as LiquidOrbPainter;
    expect(painter.usesShader, isTrue);
    final img = await _render(tester, key);
    final top = await _pixel(tester, img, 100, 40); // graphite upper fluid
    final bottom = await _pixel(tester, img, 100, 160); // mercury lower fluid
    final corner = await _pixel(tester, img, 2, 2); // outside the ball
    expect(top[3], 255);
    expect(bottom[0], greaterThan(top[0] + 40),
        reason: 'lower fluid is lighter');
    expect(corner[3], lessThan(40));
    if (Platform.environment['SAVE_LIQUID'] == '1') {
      final png = (await tester
          .runAsync(() => img.toByteData(format: ui.ImageByteFormat.png)))!;
      File('build/liquid_orb.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png.buffer.asUint8List());
    }
  });

  testWidgets('orb falls back to gradients before the shader loads',
      (tester) async {
    // No precache in this fresh isolate-like state is not guaranteed, so
    // paint the painter directly with no shader.
    final painter = LiquidOrbPainter(
      clock: ValueNotifier(0),
      motion: LiquidOrbMotion(),
      palette: LiquidPalette.graphite,
      shader: null,
      state: NeuralOrbState.idle,
      scale: 0.9,
    );
    final rec = ui.PictureRecorder();
    painter.paint(Canvas(rec), const Size(120, 120));
    rec.endRecording().dispose();
    expect(painter.usesShader, isFalse);
  });

  testWidgets('waveform, edge glow and glass rim render in both designs',
      (tester) async {
    await tester.runAsync(NeuralShaders.precache);
    for (final design in NeuralDesign.values) {
      for (final dark in [false, true]) {
        await tester.pumpWidget(harness(
          const SizedBox(
            width: 320,
            height: 400,
            child: NeuralEdgeGlow(
              level: 0.6,
              child: Column(
                children: [
                  NeuralWaveform(level: 0.7),
                  NeuralGlassCard(child: Text('Glass')),
                  NeuralOrb(state: NeuralOrbState.speaking, level: 0.5),
                ],
              ),
            ),
          ),
          dark: dark,
          design: design,
        ));
        await pumpFor(tester, const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('edge glow fades out and stops ticking when inactive',
      (tester) async {
    Widget glow(bool active) => harness(SizedBox(
          width: 200,
          height: 200,
          child: NeuralEdgeGlow(active: active, child: const SizedBox.expand()),
        ));
    await tester.pumpWidget(glow(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(glow(false));
    await pumpFor(tester, const Duration(milliseconds: 900));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('liquid widgets honour reduced motion', (tester) async {
    for (final w in const [
      NeuralLiquidOrb(),
      SizedBox(width: 200, child: NeuralWaveform(level: 0.5)),
      SizedBox(
          width: 200,
          height: 100,
          child: NeuralEdgeGlow(child: SizedBox.expand())),
    ]) {
      await expectStillUnderReducedMotion(tester, w);
    }
  });

  testWidgets('orb tile and semantics', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(harness(NeuralLiquidOrb(
      tile: true,
      state: NeuralOrbState.listening,
      onTap: () => taps++,
    )));
    await tester.tap(find.byType(NeuralLiquidOrb));
    expect(taps, 1);
    expect(find.bySemanticsLabel('AI assistant, listening'), findsOneWidget);
    expect(find.byType(Material), findsWidgets);
    handle.dispose();
  });

  test('palette stroke colors follow the design', () {
    const liquid = NeuralPalette(
      accent: Colors.red,
      secondary: Colors.blue,
      track: Colors.grey,
      foreground: Colors.black,
      surface: Colors.white,
      success: Colors.green,
      warning: Colors.orange,
      error: Colors.red,
      glowIntensity: 1,
      brightness: Brightness.light,
    );
    expect(liquid.strokeColors, NeuralSpectrum.dark);
    expect(liquid.strokeAt(0), NeuralSpectrum.dark.first);
    expect(liquid.strokeAt(1), NeuralSpectrum.dark.last);
    expect(liquid.strokeAt(double.nan), NeuralSpectrum.dark.first);
    const neon = NeuralPalette(
      accent: Colors.red,
      secondary: Colors.blue,
      track: Colors.grey,
      foreground: Colors.black,
      surface: Colors.white,
      success: Colors.green,
      warning: Colors.orange,
      error: Colors.red,
      glowIntensity: 1,
      brightness: Brightness.light,
      design: NeuralDesign.neon,
    );
    expect(neon.strokeColors, [Colors.blue, Colors.red]);
  });
}
