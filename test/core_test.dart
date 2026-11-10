import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';
import 'package:rehoboam_neural_ui/src/core/neural_clock.dart';

import 'helpers.dart';

/// Reference FNV-1a over 32-bit words, computed with BigInt.
int _fnvRef(List<int> values) {
  var h = BigInt.from(0x811C9DC5);
  final mask = BigInt.from(0xFFFFFFFF);
  for (final v in values) {
    h = (h ^ (BigInt.from(v) & mask)) * BigInt.from(16777619) & mask;
  }
  return h.toInt();
}

void main() {
  group('NeuralRandom (web-safe PRNG)', () {
    test('is deterministic and stays within 32 bits', () {
      final a = NeuralRandom(42);
      final b = NeuralRandom(42);
      for (var i = 0; i < 2000; i++) {
        final x = a.nextUint32();
        expect(x, b.nextUint32());
        expect(x, inInclusiveRange(0, 0xFFFFFFFF));
      }
    });

    test('matches the reference xorshift32 sequence', () {
      // Computed independently with uint32 arithmetic: x ^= x<<13; x ^= x>>17;
      // x ^= x<<5, seed 1.
      final r = NeuralRandom(1);
      expect([r.nextUint32(), r.nextUint32(), r.nextUint32()],
          [270369, 67634689, 2647435461]);
    });

    test('zero seed does not get stuck', () {
      final r = NeuralRandom(0);
      expect(r.nextUint32(), isNot(0));
    });

    test('nextDouble is in [0, 1)', () {
      final r = NeuralRandom(7);
      for (var i = 0; i < 5000; i++) {
        expect(r.nextDouble(), allOf(greaterThanOrEqualTo(0), lessThan(1)));
      }
    });

    test('reseed restarts the sequence', () {
      final r = NeuralRandom(9);
      final first = [r.nextUint32(), r.nextUint32()];
      r.reseed(9);
      expect([r.nextUint32(), r.nextUint32()], first);
    });
  });

  test('hash32 equals 32-bit FNV-1a without exceeding 2^53', () {
    for (final input in [
      <int>[],
      [0],
      [1, 2, 3],
      [0xFFFFFFFF, 0x12345678, 7],
      [for (var i = 0; i < 64; i++) i * 2654435761 & 0xFFFFFFFF],
    ]) {
      expect(hash32(input), _fnvRef(input), reason: '$input');
    }
  });

  test('unit / finiteOr / sanitizeSpeed handle NaN and infinities', () {
    expect(unit(double.nan), 0);
    expect(unit(double.infinity), 1);
    expect(unit(-3), 0);
    expect(unit(0.4), 0.4);
    expect(finiteOr(double.nan, 5), 5);
    expect(finiteOr(double.negativeInfinity, 5), 5);
    expect(sanitizeSpeed(double.nan), 0);
    expect(sanitizeSpeed(-1), 0);
    expect(sanitizeSpeed(100), 20);
  });

  testWidgets('NeuralClock never wraps and stops cleanly', (tester) async {
    late NeuralClock clock;
    await tester.pumpWidget(_ClockHost(onClock: (c) => clock = c));
    clock.setRunning(true);
    for (var i = 0; i < 35 * 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // A repeating 30 s controller would be back near 0 here.
    expect(clock.value, greaterThan(30));
    clock.setRunning(false);
    final frozen = clock.value;
    await tester.pump(const Duration(seconds: 1));
    expect(clock.value, frozen);
    clock.speed = double.nan;
    expect(clock.speed, 0);
    await tester.pumpWidget(const SizedBox()); // disposes; must not throw
  });

  group('NeuralThemeData', () {
    test('copyWith, lerp and equality', () {
      const a = NeuralThemeData(accent: Color(0xFF000000), glowIntensity: 0);
      const b = NeuralThemeData(accent: Color(0xFFFFFFFF), glowIntensity: 2);
      expect(a.copyWith(glowIntensity: 1).glowIntensity, 1);
      expect(a.copyWith().accent, a.accent);
      final mid = a.lerp(b, 0.5);
      expect(mid.glowIntensity, 1);
      expect(a.lerp(null, 0.5), a);
      expect(a,
          const NeuralThemeData(accent: Color(0xFF000000), glowIntensity: 0));
      expect(
          a.hashCode,
          const NeuralThemeData(accent: Color(0xFF000000), glowIntensity: 0)
              .hashCode);
    });

    testWidgets('palette resolution: widget > extension > ColorScheme',
        (tester) async {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
      late NeuralPalette fromScheme;
      late NeuralPalette fromExt;
      late NeuralPalette fromWidget;
      await tester.pumpWidget(harness(
        Builder(builder: (context) {
          fromScheme = NeuralPalette.of(context);
          return const SizedBox();
        }),
        theme: ThemeData(colorScheme: scheme),
      ));
      expect(fromScheme.accent, scheme.primary);
      expect(fromScheme.secondary, scheme.tertiary);
      expect(fromScheme.error, scheme.error);

      await tester.pumpWidget(harness(
        Builder(builder: (context) {
          fromExt = NeuralPalette.of(context);
          fromWidget = NeuralPalette.of(context, accent: Colors.pink);
          return const SizedBox();
        }),
        theme: ThemeData(
          colorScheme: scheme,
          extensions: const [
            NeuralThemeData(accent: Colors.cyan, glowIntensity: double.nan),
          ],
        ),
      ));
      await tester.pumpAndSettle(); // let the theme cross-fade finish
      expect(fromExt.accent, Colors.cyan);
      expect(fromExt.glowIntensity, 1, reason: 'NaN glow falls back to 1');
      expect(fromWidget.accent, Colors.pink);
    });

    testWidgets('dark scheme gives a dark palette', (tester) async {
      late NeuralPalette p;
      await tester.pumpWidget(harness(
        Builder(builder: (context) {
          p = NeuralPalette.of(context);
          return const SizedBox();
        }),
        dark: true,
      ));
      expect(p.isDark, isTrue);
    });
  });
}

class _ClockHost extends StatefulWidget {
  const _ClockHost({required this.onClock});
  final ValueChanged<NeuralClock> onClock;
  @override
  State<_ClockHost> createState() => _ClockHostState();
}

class _ClockHostState extends State<_ClockHost>
    with SingleTickerProviderStateMixin {
  late final NeuralClock clock = NeuralClock(this);
  @override
  void initState() {
    super.initState();
    widget.onClock(clock);
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
