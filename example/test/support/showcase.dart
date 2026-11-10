import 'package:flutter/material.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';
import 'package:rehoboam_neural_ui_example/main.dart';

/// A dense, scripted scene for the README GIF. [step] advances the story:
/// 0 ring + thinking, 1 Earth + speaking, 2 verified, 3 back to the ring.
class Showcase extends StatelessWidget {
  /// Creates the scene.
  const Showcase({super.key, required this.step});

  /// Story step.
  final int step;

  static const _chart = <List<double>>[
    [12, 18, 15, 24, 21, 30, 26, 35, 31, 42, 38, 47],
    [40, 36, 44, 39, 52, 47, 58, 50, 63, 59, 71, 76],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = galleryTheme(Brightness.dark);
    final earth = step == 1 || step == 2;
    final speaking = step == 1 || step == 2;
    Widget card(String title, Widget child) => NeuralGlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(child: Center(child: child)),
            ],
          ),
        );
    Widget row(List<Widget> children, {List<int>? flex}) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(flex: flex?[i] ?? 1, child: children[i]),
            ],
          ],
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF04060C), Color(0xFF0A1022), Color(0xFF120B24)],
            ),
          ),
          child: NeuralNetworkBackground(
            density: 0.6,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: row(flex: [
                5,
                6
              ], [
                card(
                  'AiThinkingAnimation',
                  AiThinkingAnimation(
                    size: 470,
                    level: 0.6,
                    hudMode: earth ? HudMode.earth : HudMode.ring,
                    centerLabel: 'Rehoboam',
                    topLabel: earth
                        ? 'Seismic feed\n5 events / 24 h'
                        : 'Neural core\nload 60%',
                    bottomLabel: earth
                        ? 'Tokyo, JP\n35.68 N 139.69 E'
                        : 'Divergence\nnominal',
                    targetLat: 35.68,
                    targetLon: 139.69,
                    geoPoints: const [
                      {'lat': 35.6, 'lon': 139.7, 'mag': 6.1},
                      {'lat': 37.8, 'lon': -122.4, 'mag': 4.8},
                      {'lat': -6.2, 'lon': 106.8, 'mag': 5.2},
                    ],
                  ),
                ),
                Column(
                  children: [
                    Expanded(
                      flex: 5,
                      child: row([
                        card(
                          'NeuralOrb',
                          NeuralOrb(
                            size: 150,
                            level: 0.6,
                            state: switch (step) {
                              0 => NeuralOrbState.thinking,
                              1 || 2 => NeuralOrbState.speaking,
                              _ => NeuralOrbState.listening,
                            },
                          ),
                        ),
                        card(
                          'NeuralScanRing',
                          NeuralScanRing(
                            size: 160,
                            progress: step == 0 ? 0.35 : 0.8,
                            status: step == 2
                                ? NeuralScanStatus.success
                                : NeuralScanStatus.scanning,
                            child: Icon(
                              Icons.fingerprint_rounded,
                              size: 64,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        card(
                          'NeuralGauge',
                          NeuralGauge(
                            size: 170,
                            value: speaking ? 86 : 38,
                            unit: '%',
                            label: 'Load',
                            thresholds: const [
                              NeuralGaugeThreshold(75, Color(0xFFFFC857)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      flex: 4,
                      child: row(flex: [
                        2,
                        1
                      ], [
                        card(
                          'NeuralSparkline',
                          NeuralSparkline(
                            data: _chart[speaking ? 1 : 0],
                            height: 150,
                          ),
                        ),
                        card(
                          'VoiceWave · NeuralAvatar',
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              VoiceWave(
                                size: 110,
                                level: 0.7,
                                mode: speaking
                                    ? VoiceWaveMode.speaking
                                    : VoiceWaveMode.listening,
                              ),
                              const NeuralAvatar(
                                name: 'Ada Lovelace',
                                speaking: true,
                                level: 0.7,
                                size: 60,
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
