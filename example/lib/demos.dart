import 'dart:async';
import 'dart:math' as math;

import 'package:dot_globe/dot_globe.dart';
import 'package:flutter/material.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';

/// Fake live data so every demo feels alive (mic level, typing text...).
class DemoSim extends ChangeNotifier {
  /// Starts the simulation when [run] is true.
  DemoSim({required bool run}) {
    if (run) {
      _timer = Timer.periodic(const Duration(milliseconds: 90), (_) => _tick());
    }
  }

  Timer? _timer;
  int _t = 0;

  /// Simulated audio level `0..1`.
  double level = 0.55;

  /// Words revealed in the transcript.
  int words = 9;

  /// Scan progress while scanning.
  double scan = 0.62;

  static const transcript =
      'Rehoboam, show me tomorrow\'s forecast for Tokyo and book a table near the river';

  void _tick() {
    _t++;
    final s = _t * 0.09;
    level = (0.45 +
            0.3 * math.sin(s * 3.1) * math.sin(s * 0.7) +
            0.2 * math.sin(s * 11.0))
        .clamp(0.0, 1.0);
    if (_t % 5 == 0) {
      final total = transcript.split(' ').length;
      words = words >= total + 6 ? 1 : words + 1;
    }
    scan = (scan + 0.012) % 1.05;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Lays the demo cards out in 1-3 balanced columns, hero first.
class DemoGrid extends StatefulWidget {
  /// Creates the grid.
  const DemoGrid({
    super.key,
    required this.columns,
    this.today,
    this.simulate = true,
  });

  /// Column count for the current width.
  final int columns;

  /// Fixed date for the heatmap.
  final DateTime? today;

  /// Live simulation on.
  final bool simulate;

  @override
  State<DemoGrid> createState() => _DemoGridState();
}

class _DemoGridState extends State<DemoGrid> {
  late final DemoSim _sim = DemoSim(run: widget.simulate);

  @override
  void dispose() {
    _sim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      OrbDemo(sim: _sim),
      const GaugeDemo(),
      const ChartDemo(),
      VoiceDemo(sim: _sim),
      ScanDemo(sim: _sim),
      const ProgressDemo(),
      HeatmapDemo(today: widget.today),
      AvatarDemo(sim: _sim),
      const GlassDemo(),
    ];
    const gap = 16.0;
    final n = widget.columns;
    final cols = List.generate(n, (_) => <Widget>[]);
    for (var i = 0; i < cards.length; i++) {
      cols[i % n].add(Padding(
        padding: const EdgeInsets.only(bottom: gap),
        child: cards[i],
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroDemo(wide: n > 1),
        const SizedBox(height: gap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < n; c++) ...[
              if (c > 0) const SizedBox(width: gap),
              Expanded(child: Column(children: cols[c])),
            ],
          ],
        ),
      ],
    );
  }
}

/// Shared card chrome: glass panel, widget name, title and caption.
class DemoCard extends StatelessWidget {
  /// Creates a card.
  const DemoCard({
    super.key,
    required this.widgetName,
    required this.title,
    required this.child,
    this.caption,
    this.actions = const [],
  });

  /// Class name shown as a code chip.
  final String widgetName;

  /// Human title.
  final String title;

  /// Short explanation.
  final String? caption;

  /// Demo content.
  final Widget child;

  /// Controls under the content.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return NeuralGlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widgetName,
                  style: text.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 14),
          child,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// The original Rehoboam ring / globe.
class HeroDemo extends StatefulWidget {
  /// Creates the hero.
  const HeroDemo({super.key, required this.wide});

  /// Side-by-side layout.
  final bool wide;

  @override
  State<HeroDemo> createState() => _HeroDemoState();
}

class _HeroDemoState extends State<HeroDemo> {
  HudMode _mode = HudMode.ring;
  static const _quakes = [
    {'lat': 35.6, 'lon': 139.7, 'mag': 6.1},
    {'lat': 37.8, 'lon': -122.4, 'mag': 4.8},
    {'lat': -33.4, 'lon': -70.6, 'mag': 5.4},
    {'lat': 38.0, 'lon': 23.7, 'mag': 4.2},
    {'lat': 28.6, 'lon': 77.2, 'mag': 3.9},
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dark = scheme.brightness == Brightness.dark;
    final ink = dark ? Colors.white : scheme.onSurface;
    final earth = _mode == HudMode.earth;
    final hud = LayoutBuilder(
      builder: (context, c) => AiThinkingAnimation(
        size: math.min(c.maxWidth, 420),
        level: 0.55,
        hudMode: _mode,
        color: ink,
        dotGlobeStyle: DotGlobeStyle(
          dotColor: ink.withValues(alpha: 0.85),
          sphereColor: Colors.transparent,
        ),
        centerLabel: 'Rehoboam',
        topLabel:
            earth ? 'Seismic feed\n5 events / 24 h' : 'Neural core\nload 55%',
        bottomLabel:
            earth ? 'Tokyo, JP\n35.68 N 139.69 E' : 'Divergence\nnominal',
        targetLat: 35.68,
        targetLon: 139.69,
        geoPoints: _quakes,
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('The Rehoboam HUD',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          'A living particulate ring that reacts to load, then dissolves '
          'into a dotted Earth that flies to a city and pulses every event.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        SegmentedButton<HudMode>(
          segments: const [
            ButtonSegment(
                value: HudMode.ring,
                icon: Icon(Icons.blur_circular_rounded),
                label: Text('Ring')),
            ButtonSegment(
                value: HudMode.earth,
                icon: Icon(Icons.public_rounded),
                label: Text('Earth')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
      ],
    );
    return NeuralGlassCard(
      padding: const EdgeInsets.all(20),
      child: widget.wide
          ? Row(
              children: [
                Expanded(flex: 5, child: Center(child: hud)),
                const SizedBox(width: 24),
                Expanded(flex: 4, child: info),
              ],
            )
          : Column(children: [hud, const SizedBox(height: 12), info]),
    );
  }
}

/// [NeuralOrb] with state chips.
class OrbDemo extends StatefulWidget {
  /// Creates the demo.
  const OrbDemo({super.key, required this.sim});

  /// Live data.
  final DemoSim sim;

  @override
  State<OrbDemo> createState() => _OrbDemoState();
}

class _OrbDemoState extends State<OrbDemo> {
  NeuralOrbState _state = NeuralOrbState.thinking;

  @override
  Widget build(BuildContext context) {
    return DemoCard(
      widgetName: 'NeuralOrb',
      title: 'Assistant orb',
      caption: 'Idle, listening, thinking, speaking. Tap to cycle.',
      actions: [
        for (final s in NeuralOrbState.values)
          ChoiceChip(
            label: Text(s.name),
            selected: s == _state,
            onSelected: (_) => setState(() => _state = s),
          ),
      ],
      child: Center(
        child: ListenableBuilder(
          listenable: widget.sim,
          builder: (context, _) => NeuralOrb(
            size: 170,
            state: _state,
            level: widget.sim.level,
            onTap: () => setState(() => _state = NeuralOrbState
                .values[(_state.index + 1) % NeuralOrbState.values.length]),
          ),
        ),
      ),
    );
  }
}

/// Two [NeuralGauge]s.
class GaugeDemo extends StatefulWidget {
  /// Creates the demo.
  const GaugeDemo({super.key});

  @override
  State<GaugeDemo> createState() => _GaugeDemoState();
}

class _GaugeDemoState extends State<GaugeDemo> {
  final _rng = math.Random(4);
  double _cpu = 72;
  double _mem = 41;

  @override
  Widget build(BuildContext context) {
    final palette = NeuralPalette.of(context);
    return DemoCard(
      widgetName: 'NeuralGauge',
      title: 'KPI gauges',
      caption: 'Animated sweeps, threshold colors, real text readouts.',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () => setState(() {
            _cpu = 20 + _rng.nextDouble() * 80;
            _mem = 10 + _rng.nextDouble() * 85;
          }),
          icon: const Icon(Icons.shuffle_rounded),
          label: const Text('Shuffle'),
        ),
      ],
      child: Row(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, c) => NeuralGauge(
                  size: c.maxWidth,
                  value: _cpu,
                  unit: '%',
                  label: 'CPU',
                  thresholds: [
                    NeuralGaugeThreshold(70, palette.warning),
                    NeuralGaugeThreshold(90, palette.error),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, c) => NeuralGauge(
                  size: c.maxWidth,
                  value: _mem,
                  max: 64,
                  unit: 'GB',
                  label: 'Memory',
                  sweepDegrees: 240,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [NeuralSparkline] with ranges and scrubbing.
class ChartDemo extends StatefulWidget {
  /// Creates the demo.
  const ChartDemo({super.key});

  @override
  State<ChartDemo> createState() => _ChartDemoState();
}

class _ChartDemoState extends State<ChartDemo> {
  static List<double> _series(int n, int seed) {
    final r = math.Random(seed);
    var v = 40.0;
    return [
      for (var i = 0; i < n; i++)
        v = (v + (r.nextDouble() - 0.42) * 9).clamp(8, 100).toDouble(),
    ];
  }

  final _ranges = {
    '7D': _series(7, 1),
    '30D': _series(30, 2),
    '90D': _series(90, 3),
  };
  String _range = '30D';
  int? _scrub;

  @override
  Widget build(BuildContext context) {
    final data = _ranges[_range]!;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final shown = _scrub == null ? data.last : data[_scrub!];
    final delta = (data.last - data.first) / data.first * 100;
    return DemoCard(
      widgetName: 'NeuralSparkline',
      title: 'Glowing trend',
      caption: 'Monotone curves, morphing ranges. Drag to scrub.',
      actions: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            for (final k in _ranges.keys)
              ButtonSegment(value: k, label: Text(k)),
          ],
          selected: {_range},
          onSelectionChanged: (s) => setState(() {
            _range = s.first;
            _scrub = null;
          }),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${(shown * 1000).round()}',
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _scrub == null
                      ? '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%'
                      : 'day ${_scrub! + 1}',
                  style: text.labelLarge?.copyWith(
                    color: delta >= 0 || _scrub != null
                        ? scheme.primary
                        : scheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          NeuralSparkline(
            data: data,
            height: 130,
            valueFormatter: (v) => '\$${(v * 1000).round()}',
            onScrub: (i) => setState(() => _scrub = i),
            semanticsLabel: 'Revenue, $_range',
          ),
        ],
      ),
    );
  }
}

/// [VoiceWave] + [WordByWordTranscript].
class VoiceDemo extends StatefulWidget {
  /// Creates the demo.
  const VoiceDemo({super.key, required this.sim});

  /// Live data.
  final DemoSim sim;

  @override
  State<VoiceDemo> createState() => _VoiceDemoState();
}

class _VoiceDemoState extends State<VoiceDemo> {
  VoiceWaveMode _mode = VoiceWaveMode.listening;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DemoCard(
      widgetName: 'VoiceWave',
      title: 'Voice + live transcript',
      caption: 'Aurora while listening, spectral burst while speaking.',
      actions: [
        SegmentedButton<VoiceWaveMode>(
          segments: const [
            ButtonSegment(
                value: VoiceWaveMode.listening,
                icon: Icon(Icons.mic_rounded),
                label: Text('Listen')),
            ButtonSegment(
                value: VoiceWaveMode.speaking,
                icon: Icon(Icons.graphic_eq_rounded),
                label: Text('Speak')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
      ],
      child: ListenableBuilder(
        listenable: widget.sim,
        builder: (context, _) {
          final words = DemoSim.transcript.split(' ');
          final shown = words.take(widget.sim.words.clamp(0, words.length));
          return Column(
            children: [
              VoiceWave(size: 150, mode: _mode, level: widget.sim.level),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: WordByWordTranscript(
                  text: shown.join(' '),
                  isFinal: widget.sim.words >= words.length,
                  maxLines: 2,
                  textStyle: text.titleMedium?.copyWith(height: 1.3),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// [NeuralScanRing] verify flow.
class ScanDemo extends StatefulWidget {
  /// Creates the demo.
  const ScanDemo({super.key, required this.sim});

  /// Live data.
  final DemoSim sim;

  @override
  State<ScanDemo> createState() => _ScanDemoState();
}

class _ScanDemoState extends State<ScanDemo> {
  NeuralScanStatus _status = NeuralScanStatus.scanning;

  @override
  Widget build(BuildContext context) {
    return DemoCard(
      widgetName: 'NeuralScanRing',
      title: 'Biometric scan',
      caption: 'Radar sweep, scan line, then verified or rejected.',
      actions: [
        FilledButton.tonal(
          onPressed: () => setState(() => _status = NeuralScanStatus.success),
          child: const Text('Verify'),
        ),
        OutlinedButton(
          onPressed: () => setState(() => _status = NeuralScanStatus.failure),
          child: const Text('Reject'),
        ),
        TextButton(
          onPressed: () => setState(() => _status = NeuralScanStatus.scanning),
          child: const Text('Rescan'),
        ),
      ],
      child: Center(
        child: ListenableBuilder(
          listenable: widget.sim,
          builder: (context, _) => NeuralScanRing(
            size: 176,
            status: _status,
            progress: widget.sim.scan.clamp(0, 1),
            child: Icon(
              Icons.fingerprint_rounded,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// [NeuralProgress] variants.
class ProgressDemo extends StatefulWidget {
  /// Creates the demo.
  const ProgressDemo({super.key});

  @override
  State<ProgressDemo> createState() => _ProgressDemoState();
}

class _ProgressDemoState extends State<ProgressDemo> {
  double _value = 0.68;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DemoCard(
      widgetName: 'NeuralProgress',
      title: 'Neural loaders',
      caption: 'Synapse rings and glowing bars, determinate or not.',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () => setState(
              () => _value = _value >= 1 ? 0.08 : (_value + 0.25).clamp(0, 1)),
          icon: const Icon(Icons.upload_rounded),
          label: const Text('Advance'),
        ),
      ],
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              NeuralProgress(
                value: _value,
                size: 96,
                child: Text('${(_value * 100).round()}%',
                    style:
                        text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const NeuralProgress(size: 96, semanticsLabel: 'Syncing'),
            ],
          ),
          const SizedBox(height: 16),
          NeuralProgress.linear(value: _value, semanticsLabel: 'Upload'),
          const SizedBox(height: 4),
          const NeuralProgress.linear(semanticsLabel: 'Indexing'),
        ],
      ),
    );
  }
}

/// [NeuralHeatmap] with selection.
class HeatmapDemo extends StatefulWidget {
  /// Creates the demo.
  const HeatmapDemo({super.key, this.today});

  /// Fixed date.
  final DateTime? today;

  @override
  State<HeatmapDemo> createState() => _HeatmapDemoState();
}

class _HeatmapDemoState extends State<HeatmapDemo> {
  late final DateTime _today = widget.today ?? DateTime.now();
  late final Map<DateTime, double> _values = () {
    final r = math.Random(11);
    final out = <DateTime, double>{};
    for (var i = 0; i < 26 * 7; i++) {
      final d = DateTime(_today.year, _today.month, _today.day - i);
      final weekday = d.weekday <= 5;
      final burst = math.sin(i / 9) > 0.3;
      final v = r.nextDouble() * (weekday ? 9 : 3) * (burst ? 1.6 : 0.7);
      if (r.nextDouble() > 0.18) out[d] = v.roundToDouble();
    }
    return out;
  }();
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final loc = MaterialLocalizations.of(context);
    return DemoCard(
      widgetName: 'NeuralHeatmap',
      title: 'Activity heatmap',
      caption: _picked ?? 'Tap a day. Weeks follow your locale.',
      actions: [
        Text('Less', style: text.labelSmall),
        for (final a in [0.1, 0.35, 0.6, 0.8, 1.0])
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Color.lerp(NeuralPalette.of(context).track,
                  NeuralPalette.of(context).accent, a),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        Text('More', style: text.labelSmall),
      ],
      child: LayoutBuilder(
        builder: (context, c) => NeuralHeatmap(
          values: _values,
          endDate: _today,
          weeks: c.maxWidth > 420 ? 26 : 17,
          onCellTap: (d, v) => setState(() =>
              _picked = '${loc.formatMediumDate(d)}: ${v.round()} commits'),
        ),
      ),
    );
  }
}

/// [NeuralAvatar] presence row.
class AvatarDemo extends StatelessWidget {
  /// Creates the demo.
  const AvatarDemo({super.key, required this.sim});

  /// Live data.
  final DemoSim sim;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const people = [
      ('Ada Lovelace', NeuralPresence.online, true),
      ('Alan Turing', NeuralPresence.away, false),
      ('Grace Hopper', NeuralPresence.busy, false),
      ('Claude Shannon', NeuralPresence.offline, false),
    ];
    return DemoCard(
      widgetName: 'NeuralAvatar',
      title: 'Presence aura',
      caption: 'Online, away, busy, offline, plus speaking ripples.',
      child: ListenableBuilder(
        listenable: sim,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final (name, presence, speaking) in people)
              Flexible(
                child: Column(
                  children: [
                    NeuralAvatar(
                      name: name,
                      presence: presence,
                      speaking: speaking,
                      level: sim.level,
                      size: 64,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium,
                    ),
                    Text(
                      speaking ? 'speaking' : presence.name,
                      style: text.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// [NeuralGlassCard] buttons floating on a [NeuralNetworkBackground].
class GlassDemo extends StatefulWidget {
  /// Creates the demo.
  const GlassDemo({super.key});

  @override
  State<GlassDemo> createState() => _GlassDemoState();
}

class _GlassDemoState extends State<GlassDemo> {
  double _density = 1.6;
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return DemoCard(
      widgetName: 'NeuralGlassCard',
      title: 'Glass on a living network',
      caption: 'Frosted panels with a border current. Hover, focus, tap.',
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 170,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.05),
                ),
                child: NeuralNetworkBackground(
                  density: _density,
                  linkDistance: 90,
                  seed: 21,
                  child: Center(
                    child: NeuralGlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 14),
                      borderRadius: 18,
                      onTap: () => setState(() => _taps++),
                      semanticsLabel: 'Deploy model',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.rocket_launch_rounded,
                              color: scheme.primary),
                          const SizedBox(width: 10),
                          Text(
                            _taps == 0 ? 'Deploy model' : 'Deployed x$_taps',
                            style: text.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Density', style: text.labelMedium),
              Expanded(
                child: Slider(
                  value: _density,
                  min: 0.4,
                  max: 3,
                  onChanged: (v) => setState(() => _density = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
