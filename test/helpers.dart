import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] in a themed app with optional dark mode, RTL and reduced
/// motion.
Widget harness(
  Widget child, {
  bool dark = false,
  bool rtl = false,
  bool reduceMotion = false,
  ThemeData? theme,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ??
        ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00BFA6),
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
        ),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );
}

/// Pumps [child] with reduced motion and asserts nothing keeps animating.
Future<void> expectStillUnderReducedMotion(
  WidgetTester tester,
  Widget child,
) async {
  await tester.pumpWidget(harness(child, reduceMotion: true));
  await tester.pump(const Duration(milliseconds: 50));
  expect(
    tester.binding.hasScheduledFrame,
    isFalse,
    reason: '${child.runtimeType} keeps scheduling frames although '
        'MediaQuery.disableAnimations is true',
  );
}

/// Records every [Paint] used by a canvas call, for assertions on colors
/// and stroke widths.
List<Paint> paintsUsed(WidgetTester tester, Finder customPaint) {
  final out = <Paint>[];
  final render = tester.renderObject(customPaint);
  expect(
    render,
    paints
      ..everything((method, args) {
        for (final a in args) {
          if (a is Paint) out.add(a);
        }
        return true;
      }),
  );
  return out;
}

/// Pumps [total] in 1/60 s frames (the neural clock clamps long frames).
Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const frame = Duration(microseconds: 16667);
  var t = Duration.zero;
  while (t < total) {
    await tester.pump(frame);
    t += frame;
  }
}
