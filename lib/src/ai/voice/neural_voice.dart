import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'web_speech_stub.dart' if (dart.library.js_interop) 'web_speech_web.dart'
    as platform;

/// A partial or final speech transcript.
@immutable
class NeuralTranscript {
  /// Creates a transcript.
  const NeuralTranscript(this.text, {this.isFinal = false});

  /// Recognized text so far.
  final String text;

  /// Whether recognition of this utterance is complete.
  final bool isFinal;
}

/// Progress of a spoken reply.
@immutable
class NeuralSpeechProgress {
  /// Creates a progress event.
  const NeuralSpeechProgress({this.wordIndex, this.level = 0});

  /// Index of the word being spoken (for `WordByWordTranscript`).
  final int? wordIndex;

  /// Output level `0..1` (drives the orb / HUD while speaking).
  final double level;
}

/// Speech-to-text. Implement it over any engine (`speech_to_text`,
/// Whisper, Deepgram, on-device...) or use [WebSpeechToText] /
/// [CallbackSpeechToText].
abstract class NeuralSpeechToText {
  /// Const constructor for subclasses.
  const NeuralSpeechToText();

  /// Whether this engine works on the current platform.
  bool get isAvailable;

  /// Starts listening. The stream emits partials and ends after the final
  /// transcript (or when [stop] is called).
  Stream<NeuralTranscript> listen({String? localeId});

  /// Stops listening early.
  Future<void> stop();

  /// Live microphone level `0..1`, if the engine reports one.
  Stream<double> get levels => const Stream.empty();
}

/// Text-to-speech. Implement it over any engine (`flutter_tts`, cloud
/// TTS...) or use [WebTextToSpeech] / [CallbackTextToSpeech].
abstract class NeuralTextToSpeech {
  /// Const constructor for subclasses.
  const NeuralTextToSpeech();

  /// Whether this engine works on the current platform.
  bool get isAvailable;

  /// Speaks [text]; the stream ends when speech ends.
  Stream<NeuralSpeechProgress> speak(String text, {String? localeId});

  /// Stops speaking.
  Future<void> stop();
}

/// Adapts any plugin with three functions.
///
/// ```dart
/// final stt = SpeechToText(); // package:speech_to_text
/// CallbackSpeechToText(
///   listen: (emit, level) => stt.listen(
///     onResult: (r) => emit(NeuralTranscript(r.recognizedWords, isFinal: r.finalResult)),
///     onSoundLevelChange: (db) => level(((db + 2) / 12).clamp(0, 1)),
///   ),
///   stop: stt.stop,
/// )
/// ```
class CallbackSpeechToText extends NeuralSpeechToText {
  /// Creates the adapter.
  CallbackSpeechToText({
    required this.onListen,
    required this.onStop,
    this.available = true,
  });

  /// Starts the engine; call `emit` with transcripts (a final one ends the
  /// session) and `level` with mic levels.
  final FutureOr<void> Function(
    void Function(NeuralTranscript t) emit,
    void Function(double level) level,
  ) onListen;

  /// Stops the engine.
  final FutureOr<void> Function() onStop;

  /// Platform availability.
  final bool available;

  StreamController<NeuralTranscript>? _out;
  final StreamController<double> _levels = StreamController.broadcast();

  @override
  bool get isAvailable => available;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Stream<NeuralTranscript> listen({String? localeId}) {
    _out?.close();
    final out = _out = StreamController<NeuralTranscript>();
    out.onListen = () async {
      try {
        await onListen((t) {
          if (out.isClosed) return;
          out.add(t);
          if (t.isFinal) out.close();
        }, (l) => _levels.add(l.isFinite ? l.clamp(0.0, 1.0) : 0));
      } on Object catch (e, s) {
        if (!out.isClosed) {
          out.addError(e, s);
          await out.close();
        }
      }
    };
    return out.stream;
  }

  @override
  Future<void> stop() async {
    // Capture first: a new listen() may replace _out while we await.
    final out = _out;
    await onStop();
    await out?.close();
  }
}

/// Adapts any TTS plugin.
///
/// ```dart
/// final tts = FlutterTts(); // package:flutter_tts
/// CallbackTextToSpeech(
///   speak: (text, progress) async {
///     tts.setProgressHandler((t, start, end, word) => progress(NeuralSpeechProgress(
///         wordIndex: t.substring(0, start).split(RegExp(r'\s+')).length - 1, level: 0.7)));
///     await tts.awaitSpeakCompletion(true);
///     await tts.speak(text);
///   },
///   stop: tts.stop,
/// )
/// ```
class CallbackTextToSpeech extends NeuralTextToSpeech {
  /// Creates the adapter.
  CallbackTextToSpeech({
    required this.onSpeak,
    required this.onStop,
    this.available = true,
  });

  /// Speaks; completes when speech ends. Report progress as it happens.
  final Future<void> Function(
      String text, void Function(NeuralSpeechProgress p) progress) onSpeak;

  /// Stops speaking.
  final FutureOr<void> Function() onStop;

  /// Platform availability.
  final bool available;

  @override
  bool get isAvailable => available;

  @override
  Stream<NeuralSpeechProgress> speak(String text, {String? localeId}) {
    final out = StreamController<NeuralSpeechProgress>();
    out.onListen = () async {
      try {
        await onSpeak(text, (p) {
          if (!out.isClosed) out.add(p);
        });
      } on Object catch (e, s) {
        if (!out.isClosed) out.addError(e, s);
      } finally {
        await out.close();
      }
    };
    return out.stream;
  }

  @override
  Future<void> stop() async => onStop();
}

/// The browser's built-in speech recognition (Web Speech API): no plugin,
/// no key. Available in Chromium browsers and Safari; [isAvailable] is
/// `false` elsewhere and on native platforms.
class WebSpeechToText extends NeuralSpeechToText {
  /// Creates the engine.
  WebSpeechToText();

  final platform.WebRecognizer _impl = platform.WebRecognizer();

  @override
  bool get isAvailable => _impl.isAvailable;

  @override
  Stream<NeuralTranscript> listen({String? localeId}) =>
      _impl.listen(localeId).map((r) => NeuralTranscript(r.$1, isFinal: r.$2));

  @override
  Future<void> stop() async => _impl.stop();

  @override
  Stream<double> get levels => _impl.levels;
}

/// The browser's built-in speech synthesis, with word-boundary progress.
class WebTextToSpeech extends NeuralTextToSpeech {
  /// Creates the engine.
  WebTextToSpeech({this.rate = 1, this.pitch = 1});

  /// Speaking rate (0.1 - 10).
  final double rate;

  /// Pitch (0 - 2).
  final double pitch;

  final platform.WebSynth _impl = platform.WebSynth();

  @override
  bool get isAvailable => _impl.isAvailable;

  @override
  Stream<NeuralSpeechProgress> speak(String text, {String? localeId}) {
    final words = _wordStarts(text);
    return _impl.speak(text, localeId, rate, pitch).map((charIndex) {
      var w = 0;
      while (w + 1 < words.length && words[w + 1] <= charIndex) {
        w++;
      }
      return NeuralSpeechProgress(wordIndex: w, level: 0.75);
    });
  }

  @override
  Future<void> stop() async => _impl.stop();
}

List<int> _wordStarts(String text) => [
      for (final m in RegExp(r'\S+').allMatches(text)) m.start,
    ];

/// Offline speech for demos, tests and screenshots: "hears" [phrases] in
/// turn and "speaks" at a natural pace with a synthetic level envelope.
class SimulatedSpeech {
  /// Creates simulated engines.
  SimulatedSpeech({
    this.phrases = const ['Show me the weather in Tokyo'],
    this.wordInterval = const Duration(milliseconds: 260),
  });

  /// What the simulated user says, in order (wraps around).
  final List<String> phrases;

  /// Time per word, both directions.
  final Duration wordInterval;

  int _next = 0;

  /// The speech-to-text side.
  late final NeuralSpeechToText stt = CallbackSpeechToText(
    onListen: (emit, level) async {
      final phrase = phrases.isEmpty ? '' : phrases[_next++ % phrases.length];
      final words = phrase.split(' ');
      final rnd = math.Random(_next);
      await Future<void>.delayed(wordInterval * 2);
      for (var i = 0; i < words.length; i++) {
        if (_stopped) break;
        level(0.35 + 0.6 * rnd.nextDouble());
        emit(NeuralTranscript(words.take(i + 1).join(' ')));
        await Future<void>.delayed(wordInterval);
      }
      level(0);
      emit(NeuralTranscript(phrase, isFinal: true));
      _stopped = false;
    },
    onStop: () => _stopped = true,
  );

  bool _stopped = false;
  bool _ttsStopped = false;

  /// The text-to-speech side.
  late final NeuralTextToSpeech tts = CallbackTextToSpeech(
    onSpeak: (text, progress) async {
      _ttsStopped = false;
      final n = RegExp(r'\S+').allMatches(text).length;
      for (var i = 0; i < n; i++) {
        if (_ttsStopped) break;
        progress(NeuralSpeechProgress(
            wordIndex: i, level: 0.45 + 0.5 * math.sin(i * 1.7).abs()));
        await Future<void>.delayed(wordInterval);
      }
      progress(const NeuralSpeechProgress(level: 0));
    },
    onStop: () => _ttsStopped = true,
  );
}
