import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';
import 'package:rehoboam_neural_ui_example/main.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  for (final size in const [
    Size(390, 844),
    Size(900, 1100),
    Size(1440, 1000)
  ]) {
    testWidgets('gallery renders every widget at ${size.width.toInt()} px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(GalleryApp(today: DateTime(2026, 11, 10)));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      for (final t in [
        AiThinkingAnimation,
        NeuralNetworkBackground,
        NeuralGlassCard,
      ]) {
        expect(find.byType(t), findsWidgets, reason: '$t');
      }
      // Scroll through so lazily built cards mount too.
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await _settle(tester);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('theme and direction toggles work', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GalleryApp(today: DateTime(2026, 11, 10)));
    await _settle(tester);
    BuildContext ctx() => tester.element(find.byType(GalleryHome));
    expect(Theme.of(ctx()).brightness, Brightness.dark);
    await tester.tap(find.byTooltip('Light mode'));
    await _settle(tester);
    await _settle(tester);
    expect(Theme.of(ctx()).brightness, Brightness.light);
    await tester.tap(find.byTooltip('Right to left'));
    await _settle(tester);
    expect(Directionality.of(ctx()), TextDirection.rtl);
    await tester.tap(find.text('Earth'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
