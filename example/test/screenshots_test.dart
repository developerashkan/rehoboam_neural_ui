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
    addTearDown(tester.view.reset);

    // Desktop, dark, full page (also the source of the README tiles).
    await _fullPage(tester, GalleryApp(key: UniqueKey(), today: _today), 1440);
    await _frames(tester, const Duration(milliseconds: 1800));
    await _cardRects(tester, 'dark');
    await capturePng(tester, _key, '$_out/gallery_dark.png', pixelRatio: 1.5);

    // Desktop, light, Earth mode on the hero.
    await _fullPage(
        tester,
        GalleryApp(
            key: UniqueKey(), today: _today, initialMode: ThemeMode.light),
        1440);
    await tester.tap(find.text('Earth'));
    await _frames(tester, const Duration(milliseconds: 3600));
    await _cardRects(tester, 'light');
    await capturePng(tester, _key, '$_out/gallery_light.png', pixelRatio: 1.5);

    // Phones.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(RepaintBoundary(
        key: _key, child: GalleryApp(key: UniqueKey(), today: _today)));
    await _frames(tester, const Duration(milliseconds: 1800));
    await capturePng(tester, _key, '$_out/phone_dark.png', pixelRatio: 3);

    await tester.pumpWidget(RepaintBoundary(
      key: _key,
      child: GalleryApp(
        key: UniqueKey(),
        today: _today,
        initialMode: ThemeMode.light,
        initialRtl: true,
      ),
    ));
    await _frames(tester, const Duration(milliseconds: 300));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -560));
    await _frames(tester, const Duration(milliseconds: 1800));
    await capturePng(tester, _key, '$_out/phone_light_rtl.png', pixelRatio: 3);

    await tester.pumpWidget(const SizedBox());
    await _frames(tester, const Duration(milliseconds: 100));
  });

  testWidgets('gif frames', (tester) async {
    if (!_capture) return;
    await loadRealFonts(tester);
    await tester.runAsync(DotGlobeGeometry.load);
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
