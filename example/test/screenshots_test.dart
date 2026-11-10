// Renders the README / pub.dev screenshots and GIF frames with real fonts.
//
//   cd example
//   flutter test test/screenshots_test.dart --dart-define=CAPTURE=true
//   python tool/make_media.py
//
// Writes ../assets/screenshots/*.png, build/cards_*.json (card rects for
// the README tiles) and build/frames/*.png (GIF frames).
import 'dart:convert';
import 'dart:io';

import 'package:dot_globe/dot_globe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';
import 'package:rehoboam_neural_ui_example/demos.dart';
import 'package:rehoboam_neural_ui_example/main.dart';

import 'support/capture.dart';
import 'support/showcase.dart';

const _capture = bool.fromEnvironment('CAPTURE');
const _out = '../assets/screenshots';
final _today = DateTime(2026, 11, 10);
final _key = GlobalKey();

Future<void> _frames(WidgetTester tester, Duration d) async {
  const f = Duration(microseconds: 16667);
  for (var t = Duration.zero; t < d; t += f) {
    await tester.pump(f);
  }
}

const _cards = {
  'liquid': LiquidDemo,
  'hero': HeroDemo,
  'orb': OrbDemo,
  'gauge': GaugeDemo,
  'chart': ChartDemo,
  'voice': VoiceDemo,
  'scan': ScanDemo,
  'progress': ProgressDemo,
  'heatmap': HeatmapDemo,
  'avatar': AvatarDemo,
  'glass': GlassDemo,
};

/// Pumps [app] at [width] and grows the surface until nothing scrolls, so
/// the whole dashboard is in one image.
Future<void> _fullPage(WidgetTester tester, Widget app, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1600);
  await tester.pumpWidget(RepaintBoundary(key: _key, child: app));
  await _frames(tester, const Duration(milliseconds: 300));
  final pos =
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  final extra = pos.maxScrollExtent;
  tester.view.physicalSize = Size(width, 1600 + extra);
  await tester.pump();
}

Future<void> _cardRects(WidgetTester tester, String name) async {
  final rects = <String, List<double>>{};
  _cards.forEach((k, t) {
    final f = find.byType(t);
    if (f.evaluate().isEmpty) return;
    final r = tester.getRect(f.first);
    rects[k] = [r.left, r.top, r.right, r.bottom];
  });
  final file = File('build/cards_$name.json');
  await tester.runAsync(() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(rects));
  });
}

void main() {
  testWidgets('screenshots', (tester) async {
    if (!_capture) return;
    await loadRealFonts(tester);
    await tester.runAsync(DotGlobeGeometry.load);
    await tester.runAsync(NeuralShaders.precache);
    addTearDown(tester.view.reset);

    Future<void> screen(Widget app, String name, Size size,
        {double ratio = 1.5, Future<void> Function()? before}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(RepaintBoundary(key: _key, child: app));
      await _frames(tester, const Duration(milliseconds: 400));
      if (before != null) await before();
      await _frames(tester, const Duration(milliseconds: 600));
      await capturePng(tester, _key, '$_out/$name.png', pixelRatio: ratio);
    }

    // 1. The liquid orb, presented like an app icon (README hero still).
    await screen(const _OrbHero(), 'liquid_orb', const Size(1200, 560));

    // 2. Assistant: a finished tool + generated-UI conversation.
    Future<void> ask(String q) async {
      await tester.tap(find.text(q).first);
      await _frames(tester, const Duration(seconds: 7));
    }

    await screen(
      GalleryApp(key: UniqueKey(), today: _today),
      'assistant_dark',
      const Size(1440, 940),
      before: () => ask('Server dashboard'),
    );
    await screen(
      GalleryApp(key: UniqueKey(), today: _today, initialMode: ThemeMode.light),
      'phone_assistant_light',
      const Size(390, 844),
      ratio: 3,
      before: () => ask('Weather in Lisbon'),
    );

    // 3. HUD: the model flew the globe to Tokyo.
    await screen(
      GalleryApp(key: UniqueKey(), today: _today, initialTab: GalleryTab.hud),
      'hud_earth_dark',
      const Size(1440, 940),
      before: () async {
        await tester.tap(find.text('Show me Tokyo'));
        await _frames(tester, const Duration(seconds: 8));
      },
    );
    await screen(
      GalleryApp(
        key: UniqueKey(),
        today: _today,
        initialTab: GalleryTab.hud,
        initialMode: ThemeMode.light,
      ),
      'phone_hud_light',
      const Size(390, 844),
      ratio: 3,
    );

    // 4. Every widget, liquid (dark, light) and neon, full page.
    for (final (name, mode, design) in [
      ('gallery_dark', ThemeMode.dark, NeuralDesign.liquid),
      ('gallery_light', ThemeMode.light, NeuralDesign.liquid),
      ('gallery_neon', ThemeMode.dark, NeuralDesign.neon),
    ]) {
      await _fullPage(
        tester,
        GalleryApp(
          key: UniqueKey(),
          today: _today,
          initialMode: mode,
          initialDesign: design,
          initialTab: GalleryTab.widgets,
        ),
        1440,
      );
      if (name != 'gallery_neon') {
        await tester.tap(find.text('Earth'));
      }
      await _frames(tester, const Duration(milliseconds: 3600));
      await _cardRects(tester, name.replaceFirst('gallery_', ''));
      await capturePng(tester, _key, '$_out/$name.png', pixelRatio: 1.25);
    }

    // 5. Right-to-left phone.
    await screen(
      GalleryApp(
        key: UniqueKey(),
        today: _today,
        initialTab: GalleryTab.widgets,
        initialRtl: true,
      ),
      'phone_widgets_rtl',
      const Size(390, 844),
      ratio: 3,
      before: () async {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -560));
      },
    );

    await tester.pumpWidget(const SizedBox());
    await _frames(tester, const Duration(milliseconds: 100));
  });

  testWidgets('gif frames', (tester) async {
    if (!_capture) return;
    await loadRealFonts(tester);
    await tester.runAsync(DotGlobeGeometry.load);
    await tester.runAsync(NeuralShaders.precache);
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 675);
    Future<void> scene(int step) => tester
        .pumpWidget(RepaintBoundary(key: _key, child: Showcase(step: step)));
    await scene(0);
    await _frames(tester, const Duration(milliseconds: 1200));

    var n = 0;
    // 12 fps: one frame every 5 pumps of 1/60 s.
    Future<void> record(Duration d) async {
      const f = Duration(microseconds: 16667);
      var i = 0;
      for (var t = Duration.zero; t < d; t += f) {
        await tester.pump(f);
        if (i++ % 5 == 0) {
          await capturePng(tester, _key,
              'build/frames/f${(n++).toString().padLeft(3, '0')}.png',
              pixelRatio: 0.8);
        }
      }
    }

    await record(const Duration(milliseconds: 1500));
    await scene(1); // Earth, speaking, gauge up, new series
    await record(const Duration(milliseconds: 3200));
    await scene(2); // verified
    await record(const Duration(milliseconds: 1500));
    await scene(3); // back to the ring, listening
    await record(const Duration(milliseconds: 2300));

    await tester.pumpWidget(const SizedBox());
    await _frames(tester, const Duration(milliseconds: 100));
  });
}

/// The liquid orb as an app-icon tile, flanked by palettes.
class _OrbHero extends StatelessWidget {
  const _OrbHero();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: galleryTheme(Brightness.light),
      home: Scaffold(
        backgroundColor: const Color(0xFFE9E9EE),
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final (p, size) in const [
                (LiquidPalette.aurora, 150.0),
                (LiquidPalette.ocean, 190.0),
                (LiquidPalette.graphite, 300.0),
                (LiquidPalette.ember, 190.0),
                (LiquidPalette.orchid, 150.0),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: NeuralLiquidOrb(
                    size: size,
                    tile: true,
                    palette: p,
                    state: NeuralOrbState.speaking,
                    level: 0.4,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
