import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';
import 'package:rehoboam_neural_ui_example/main.dart';

Future<void> _frames(WidgetTester tester, Duration d) async {
  const f = Duration(microseconds: 16667);
  for (var t = Duration.zero; t < d; t += f) {
    await tester.pump(f);
  }
}

void _size(WidgetTester tester, Size s) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = s;
  addTearDown(tester.view.reset);
}

void main() {
  for (final size in const [Size(390, 844), Size(1440, 1000)]) {
    for (final tab in GalleryTab.values) {
      testWidgets('${tab.name} renders at ${size.width.toInt()} px',
          (tester) async {
        _size(tester, size);
        await tester.pumpWidget(
            GalleryApp(today: DateTime(2026, 11, 10), initialTab: tab));
        await _frames(tester, const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        if (tab == GalleryTab.widgets) {
          for (var i = 0; i < 8; i++) {
            await tester.drag(
                find.byType(CustomScrollView), const Offset(0, -600));
            await _frames(tester, const Duration(milliseconds: 200));
          }
          expect(find.byType(NeuralGlassCard), findsWidgets);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('assistant answers with a tool and generated UI', (tester) async {
    _size(tester, const Size(430, 900));
    await tester.pumpWidget(GalleryApp(today: DateTime(2026, 11, 10)));
    await _frames(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Weather in Lisbon'));
    await _frames(tester, const Duration(seconds: 6));
    expect(find.textContaining('Used get weather'), findsOneWidget);
    expect(find.textContaining('Next 8 hours'), findsOneWidget);
    expect(find.byType(NeuralSparkline), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('HUD flies to a place through the model', (tester) async {
    _size(tester, const Size(1200, 900));
    await tester.pumpWidget(
        GalleryApp(today: DateTime(2026, 11, 10), initialTab: GalleryTab.hud));
    await _frames(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Show me Tokyo'));
    await _frames(tester, const Duration(seconds: 6));
    final hud =
        tester.widget<AiThinkingAnimation>(find.byType(AiThinkingAnimation));
    expect(hud.hudMode, HudMode.earth);
    expect(hud.bottomLabel, 'Tokyo, JP');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('theme, direction and design toggles work', (tester) async {
    _size(tester, const Size(1200, 1000));
    await tester.pumpWidget(GalleryApp(
        today: DateTime(2026, 11, 10), initialTab: GalleryTab.widgets));
    await _frames(tester, const Duration(milliseconds: 300));
    BuildContext ctx() => tester.element(find.byType(GalleryShell));
    expect(Theme.of(ctx()).brightness, Brightness.dark);
    await tester.tap(find.byTooltip('Light mode'));
    await _frames(tester, const Duration(milliseconds: 600));
    expect(Theme.of(ctx()).brightness, Brightness.light);
    await tester.tap(find.byTooltip('Right to left'));
    await _frames(tester, const Duration(milliseconds: 200));
    expect(Directionality.of(ctx()), TextDirection.rtl);
    await tester.tap(find.byTooltip('Neon design'));
    await _frames(tester, const Duration(milliseconds: 600));
    expect(NeuralPalette.of(ctx()).isLiquid, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
