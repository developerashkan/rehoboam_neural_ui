import 'package:dot_globe/dot_globe.dart';
import 'package:flutter/material.dart';

import '../rehoboam.dart';
import 'neural_agent.dart';
import 'neural_tool.dart';

/// Drives an [AiThinkingAnimation] from code, from voice and from an AI.
///
/// * [bindAgent] links it to a [NeuralAgent]: the ring breathes with the
///   microphone while listening, speeds up and spikes while the assistant
///   answers or speaks, and the captions follow the agent's phase.
/// * [tools] let the model operate the HUD itself ("show me Tokyo" ->
///   the ring dissolves into the globe and flies there).
class RehoboamController extends ChangeNotifier {
  /// Creates a controller.
  RehoboamController({
    HudMode mode = HudMode.ring,
    this.centerLabel = 'Rehoboam',
    this.topLabel,
    this.bottomLabel,
  }) : _mode = mode;

  HudMode _mode;
  double? _lat;
  double? _lon;
  AiFaceMode _face = AiFaceMode.listening;
  List<Map<String, double>> _points = const [];
  final ValueNotifier<double> _level = ValueNotifier(0);
  NeuralAgent? _agent;

  /// Center caption.
  String? centerLabel;

  /// Top caption.
  String? topLabel;

  /// Bottom caption.
  String? bottomLabel;

  /// Ring or Earth.
  HudMode get mode => _mode;

  /// Target latitude.
  double? get latitude => _lat;

  /// Target longitude.
  double? get longitude => _lon;

  /// Listening or speaking texture.
  AiFaceMode get face => _face;

  /// Globe markers.
  List<Map<String, double>> get points => _points;

  /// Energy `0..1` (updates at audio rate; listened to separately).
  ValueNotifier<double> get level => _level;

  /// Dissolves into the globe and flies to [lat] / [lon].
  void showOnGlobe(double lat, double lon, {String? label, String? detail}) {
    _lat = lat.clamp(-90.0, 90.0);
    _lon = ((lon + 180) % 360 + 360) % 360 - 180;
    _mode = HudMode.earth;
    if (label != null) bottomLabel = label;
    if (detail != null) topLabel = detail;
    notifyListeners();
  }

  /// Back to the ring.
  void showRing({String? label}) {
    _mode = HudMode.ring;
    if (label != null) bottomLabel = label;
    notifyListeners();
  }

  /// Replaces the globe markers (`lat`, `lon`, optional `mag`).
  void setPoints(List<Map<String, double>> points) {
    // A new list identity only when the points change (the HUD rebuilds
    // its markers on identity changes, not at audio rate).
    _points = List.unmodifiable(points);
    notifyListeners();
  }

  /// Updates captions.
  void setLabels({String? center, String? top, String? bottom}) {
    centerLabel = center ?? centerLabel;
    topLabel = top ?? topLabel;
    bottomLabel = bottom ?? bottomLabel;
    notifyListeners();
  }

  /// Follows [agent]'s phase and voice level (pass `null` to unbind).
  void bindAgent(NeuralAgent? agent) {
    _agent?.removeListener(_onAgent);
    _agent?.level.removeListener(_onLevel);
    _agent = agent;
    agent?.addListener(_onAgent);
    agent?.level.addListener(_onLevel);
    if (agent != null) _onAgent();
  }

  void _onLevel() {
    final a = _agent;
    if (a == null) return;
    _level.value = a.level.value;
  }

  void _onAgent() {
    final a = _agent!;
    final speaking = a.phase == NeuralAgentPhase.responding ||
        a.phase == NeuralAgentPhase.speaking;
    final face = speaking ? AiFaceMode.speaking : AiFaceMode.listening;
    final caption = switch (a.phase) {
      NeuralAgentPhase.idle => 'Standing by',
      NeuralAgentPhase.listening => 'Listening',
      NeuralAgentPhase.thinking => 'Thinking',
      NeuralAgentPhase.responding => 'Responding',
      NeuralAgentPhase.usingTool => 'Running ${a.activeTool ?? 'tool'}',
      NeuralAgentPhase.speaking => 'Speaking',
      NeuralAgentPhase.error => 'Signal lost',
    };
    // Thinking with no voice still deserves some energy.
    if (a.phase == NeuralAgentPhase.thinking ||
        a.phase == NeuralAgentPhase.usingTool) {
      _level.value = 0.45;
    } else if (a.phase == NeuralAgentPhase.responding) {
      _level.value = 0.7;
    } else if (a.phase == NeuralAgentPhase.idle) {
      _level.value = 0.15;
    }
    if (face != _face || caption != topLabel) {
      _face = face;
      topLabel = caption;
      notifyListeners();
    }
  }

  /// Tools that let a model operate this HUD.
  List<NeuralTool> get tools => [
        NeuralTool(
          name: 'show_on_globe',
          description:
              'Turn the Rehoboam HUD into a 3D Earth and fly to a place. '
              'Use whenever a location is discussed. Optional points mark events.',
          parameters: const {
            'type': 'object',
            'properties': {
              'latitude': {'type': 'number', 'description': '-90..90'},
              'longitude': {'type': 'number', 'description': '-180..180'},
              'label': {
                'type': 'string',
                'description': 'Short caption, e.g. "Tokyo, JP"'
              },
              'points': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'lat': {'type': 'number'},
                    'lon': {'type': 'number'},
                    'mag': {'type': 'number'},
                  },
                  'required': ['lat', 'lon'],
                },
              },
            },
            'required': ['latitude', 'longitude'],
          },
          handler: (args, ctx) {
            final pts = args['points'];
            if (pts is List) {
              setPoints([
                for (final p in pts.whereType<Map>())
                  {
                    'lat': (p['lat'] as num).toDouble(),
                    'lon': (p['lon'] as num).toDouble(),
                    if (p['mag'] is num) 'mag': (p['mag'] as num).toDouble(),
                  },
              ]);
            }
            showOnGlobe(
              (args['latitude']! as num).toDouble(),
              (args['longitude']! as num).toDouble(),
              label: args['label'] as String?,
            );
            return {'shown': true};
          },
        ),
        NeuralTool(
          name: 'show_hud_ring',
          description: 'Return the Rehoboam HUD to its neural ring view.',
          parameters: const {
            'type': 'object',
            'properties': {
              'label': {'type': 'string'},
            },
          },
          handler: (args, ctx) {
            showRing(label: args['label'] as String?);
            return {'shown': true};
          },
        ),
      ];

  @override
  void dispose() {
    bindAgent(null);
    _level.dispose();
    super.dispose();
  }
}

/// An [AiThinkingAnimation] driven by a [RehoboamController].
class RehoboamHud extends StatelessWidget {
  /// Creates the HUD.
  const RehoboamHud({
    super.key,
    required this.controller,
    this.size = 320,
    this.color,
    this.dotGlobeStyle,
    this.dotGlobeController,
  });

  /// The controller.
  final RehoboamController controller;

  /// Side length.
  final double size;

  /// Ring and caption ink.
  final Color? color;

  /// Globe colors (defaults follow [color]).
  final DotGlobeStyle? dotGlobeStyle;

  /// Optional globe controller.
  final DotGlobeController? dotGlobeController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.level]),
      builder: (context, _) {
        final ink = color ??
            (Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface);
        return AiThinkingAnimation(
          size: size,
          level: controller.level.value,
          mode: controller.face,
          hudMode: controller.mode,
          color: ink,
          centerLabel: controller.centerLabel,
          topLabel: controller.topLabel,
          bottomLabel: controller.bottomLabel,
          targetLat: controller.latitude,
          targetLon: controller.longitude,
          geoPoints: controller.points,
          dotGlobeController: dotGlobeController,
          dotGlobeStyle: dotGlobeStyle ??
              DotGlobeStyle(
                dotColor: ink.withValues(alpha: 0.85),
                sphereColor: Colors.transparent,
              ),
        );
      },
    );
  }
}
