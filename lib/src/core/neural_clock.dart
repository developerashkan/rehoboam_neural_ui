import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A monotonic animation clock in seconds that drives a painter's `repaint`
/// listenable directly, so continuous animations never rebuild widgets.
///
/// Unlike a repeating `AnimationController`, the value never wraps, so
/// periodic motion built from it has no visible jump at the loop point, and
/// changing [speed] mid-flight never makes the animation skip.
class NeuralClock extends ChangeNotifier implements ValueListenable<double> {
  /// Creates a stopped clock bound to [vsync].
  NeuralClock(TickerProvider vsync, {double speed = 1}) : _speed = speed {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _value = 0;
  double _speed;
  bool _disposed = false;

  /// Extra per-tick work (physics, smoothing) run before listeners repaint.
  /// Receives the frame's delta in (speed-scaled) seconds.
  void Function(double dt)? onTick;

  /// Elapsed animation time in seconds.
  @override
  double get value => _value;

  /// Time multiplier. Non-finite or negative values are treated as `0`.
  double get speed => _speed;
  set speed(double v) => _speed = sanitizeSpeed(v);

  /// Whether the clock is advancing.
  bool get isRunning => _ticker.isActive;

  /// Starts or stops the clock. Stopping keeps the current [value] so a
  /// paused widget shows a stable frame.
  void setRunning(bool running) {
    if (_disposed) return;
    if (running && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!running && _ticker.isActive) {
      _ticker.stop();
    }
  }

  /// Advances the clock manually (used by tests and when animations are
  /// disabled but a single state change must still land).
  void advance(double seconds) {
    if (_disposed) return;
    final dt = seconds.isFinite ? seconds : 0.0;
    _value += dt * _speed;
    onTick?.call(dt * _speed);
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    // Clamp so a long pause (backgrounded app, muted TickerMode) resumes
    // smoothly instead of teleporting the simulation forward.
    final dt =
        ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 15).toDouble();
    _last = elapsed;
    _value += dt * _speed;
    onTick?.call(dt * _speed);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    super.dispose();
  }
}

/// Clamps an animation speed multiplier to a safe, finite range.
double sanitizeSpeed(double v) => v.isFinite ? v.clamp(0.0, 20.0) : 0.0;

/// Clamps [v] to `[0, 1]`; `NaN` and infinities map to `0` / `1`.
double unit(double v) {
  if (v.isNaN) return 0;
  return v.clamp(0.0, 1.0);
}

/// Returns [v] if finite, otherwise [fallback].
double finiteOr(double v, double fallback) => v.isFinite ? v : fallback;

/// Whether the platform asked for reduced motion.
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A tiny xorshift32 PRNG.
///
/// Uses only shifts, xors and 32-bit masks, so it produces the same
/// sequence on the Dart VM and on the web (where integers are doubles and
/// anything above 2^53 silently loses precision, which breaks the usual
/// multiply-based hashes).
class NeuralRandom {
  /// Seeds the generator. A zero seed is remapped (xorshift's fixed point).
  NeuralRandom(int seed)
      : _s = (seed & 0xFFFFFFFF) == 0 ? 0x9E3779B9 : seed & 0xFFFFFFFF;

  int _s;

  /// Restarts the sequence from [seed] without allocating a new generator.
  void reseed(int seed) =>
      _s = (seed & 0xFFFFFFFF) == 0 ? 0x9E3779B9 : seed & 0xFFFFFFFF;

  /// Next raw 32-bit unsigned value.
  int nextUint32() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _s = x & 0xFFFFFFFF;
    return _s;
  }

  /// Uniform double in `[0, 1)`.
  double nextDouble() => nextUint32() / 4294967296.0;
}

/// A web-safe 32-bit FNV-1a style hash of [values], computed with
/// shift-add multiplication so no intermediate exceeds 2^53.
int hash32(Iterable<int> values) {
  var h = 0x811C9DC5;
  for (final v in values) {
    h ^= v & 0xFFFFFFFF;
    // h * 16777619 (FNV prime) == h * 2^24 + h * 403; split so every partial
    // product stays below 2^53 on the web.
    h = ((h << 24) & 0xFFFFFFFF) + ((h * 403) & 0xFFFFFFFF);
    h &= 0xFFFFFFFF;
  }
  return h;
}
