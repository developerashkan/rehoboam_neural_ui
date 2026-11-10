import 'dart:async';
import 'dart:ui' as ui;

/// The package's fragment shaders.
enum NeuralShader {
  /// Glass sphere with two fluids and a prismatic interface.
  liquidOrb('liquid_orb'),

  /// Translucent voice ribbons.
  liquidWave('liquid_wave'),

  /// Iridescent assistant glow along a rounded edge.
  edgeGlow('edge_glow'),

  /// Light on the rim of a glass slab.
  liquidGlass('liquid_glass');

  const NeuralShader(this.fileName);

  /// File stem in `shaders/`.
  final String fileName;

  /// Asset key when the package is a dependency.
  String get assetKey => 'packages/rehoboam_neural_ui/shaders/$fileName.frag';
}

/// Loads and caches the compiled shaders.
///
/// Widgets load lazily and paint a gradient fallback until the program is
/// ready (or forever, if a platform cannot compile it), so calling
/// [precache] is optional. Call it before `runApp` for a perfect first
/// frame:
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await NeuralShaders.precache();
///   runApp(const App());
/// }
/// ```
abstract final class NeuralShaders {
  static final Map<NeuralShader, ui.FragmentProgram> _ready = {};
  static final Map<NeuralShader, Future<ui.FragmentProgram?>> _pending = {};
  static final Set<NeuralShader> _failed = {};

  /// The program, if it has finished loading.
  static ui.FragmentProgram? cached(NeuralShader s) => _ready[s];

  /// Whether loading [s] failed (the widget keeps its fallback).
  static bool failed(NeuralShader s) => _failed.contains(s);

  /// Loads [s] once. Completes with `null` if it cannot be loaded.
  static Future<ui.FragmentProgram?> load(NeuralShader s) {
    final ready = _ready[s];
    if (ready != null) return Future.value(ready);
    if (_failed.contains(s)) return Future.value(null);
    return _pending.putIfAbsent(s, () async {
      try {
        ui.FragmentProgram program;
        try {
          program = await ui.FragmentProgram.fromAsset(s.assetKey);
        } on Object {
          // Inside this package's own tests the key has no package prefix.
          program =
              await ui.FragmentProgram.fromAsset('shaders/${s.fileName}.frag');
        }
        _ready[s] = program;
        return program;
      } on Object {
        _failed.add(s);
        return null;
      } finally {
        unawaited(_pending.remove(s));
      }
    });
  }

  /// Loads every shader (or [shaders]); never throws.
  static Future<void> precache([
    Iterable<NeuralShader> shaders = NeuralShader.values,
  ]) =>
      Future.wait(shaders.map(load));
}
