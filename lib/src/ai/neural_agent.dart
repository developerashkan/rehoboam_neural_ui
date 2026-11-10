import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../widgets/neural_orb.dart' show NeuralOrbState;
import 'gen_ui.dart';
import 'neural_message.dart';
import 'neural_model.dart';
import 'neural_tool.dart';
import 'voice/neural_voice.dart';

/// What a [NeuralAgent] is doing right now.
enum NeuralAgentPhase {
  /// Waiting for input.
  idle,

  /// Hearing the user (speech-to-text running).
  listening,

  /// Waiting for the model's first token.
  thinking,

  /// Streaming the answer.
  responding,

  /// Running tools.
  usingTool,

  /// Reading the answer aloud.
  speaking,

  /// The last turn failed; see [NeuralAgent.error].
  error,
}

/// A conversation with any [NeuralModel]: streaming, multi-step tool use,
/// generated UI, retries, cancellation and optional voice.
///
/// It is a [ChangeNotifier] (phase, messages, errors) and exposes cheap
/// [ValueListenable]s for per-token and per-frame data, so a chat view
/// rebuilds only what changes. Every neural widget can be driven by it:
/// [orbState] and [level] for orbs and the HUD, [streamingText] for
/// `WordByWordTranscript`, [spokenWord] for read-along highlighting.
///
/// ```dart
/// final agent = NeuralAgent(
///   model: ClaudeModel(baseUrl: 'https://my-proxy.example.com'),
///   system: 'You are a concise assistant.',
///   tools: [weatherTool],
///   uiCatalog: NeuralUiCatalog.standard(),
/// );
/// await agent.send('What is the weather in Lisbon?');
/// ```
class NeuralAgent extends ChangeNotifier {
  /// Creates an agent.
  NeuralAgent({
    required NeuralModel model,
    this.system,
    List<NeuralTool> tools = const [],
    this.uiCatalog,
    this.maxSteps = 8,
    this.maxRetries = 2,
    this.maxOutputTokens,
    this.speechToText,
    this.textToSpeech,
    this.speakReplies = false,
    this.onApproveTool,
    this.localeId,
    List<NeuralMessage>? history,
  })  : _model = model,
        _tools = List.of(tools),
        _messages = List.of(history ?? const []);

  NeuralModel _model;
  final List<NeuralTool> _tools;
  final List<NeuralMessage> _messages;

  /// System instructions sent with every request.
  String? system;

  /// Components the model may render (adds the `render_ui` tool).
  final NeuralUiCatalog? uiCatalog;

  /// Maximum model calls per user turn (tool loops stop here).
  final int maxSteps;

  /// Retries for rate limits, overload and network errors.
  final int maxRetries;

  /// Output cap per call (provider default when `null`).
  final int? maxOutputTokens;

  /// Speech input, used by [listen].
  NeuralSpeechToText? speechToText;

  /// Speech output, used by [speak] and [speakReplies].
  NeuralTextToSpeech? textToSpeech;

  /// Read every final answer aloud.
  bool speakReplies;

  /// Locale for speech (`en-US`, `fa-IR`...).
  String? localeId;

  /// Asked before running a tool with `requiresApproval`. Return `false`
  /// to decline; the model is told the user declined.
  Future<bool> Function(NeuralToolCall call)? onApproveTool;

  NeuralAgentPhase _phase = NeuralAgentPhase.idle;
  Object? _error;
  NeuralFinishEvent? _lastFinish;
  NeuralCancelToken? _cancel;
  StreamSubscription<Object?>? _voiceSub;
  bool _disposed = false;
  int _inputTokens = 0;
  int _outputTokens = 0;
  String? _activeTool;

  final ValueNotifier<String> _streaming = ValueNotifier('');
  final ValueNotifier<String> _reasoning = ValueNotifier('');
  final ValueNotifier<String> _live = ValueNotifier('');
  final ValueNotifier<double> _level = ValueNotifier(0);
  final ValueNotifier<int?> _word = ValueNotifier(null);

  /// The model in use. Swap it at any time between turns.
  NeuralModel get model => _model;
  set model(NeuralModel m) {
    _model = m;
    _notify();
  }

  /// Registered tools (plus `render_ui` when a [uiCatalog] is set).
  List<NeuralTool> get tools => [
        ..._tools,
        if (uiCatalog != null) uiCatalog!.tool,
      ];

  /// Adds a tool.
  void addTool(NeuralTool tool) {
    _tools.removeWhere((t) => t.name == tool.name);
    _tools.add(tool);
  }

  /// The conversation (oldest first).
  List<NeuralMessage> get messages => List.unmodifiable(_messages);

  /// Current phase.
  NeuralAgentPhase get phase => _phase;

  /// Whether a turn or voice session is in progress.
  bool get isBusy =>
      _phase != NeuralAgentPhase.idle && _phase != NeuralAgentPhase.error;

  /// The last error, if [phase] is [NeuralAgentPhase.error].
  Object? get error => _error;

  /// How the last model call ended (refusals are reported here).
  NeuralFinishEvent? get lastFinish => _lastFinish;

  /// The tool running now, if any.
  String? get activeTool => _activeTool;

  /// Tokens used in this conversation.
  ({int input, int output}) get usage =>
      (input: _inputTokens, output: _outputTokens);

  /// The answer being streamed (empty between turns).
  ValueListenable<String> get streamingText => _streaming;

  /// The reasoning summary being streamed.
  ValueListenable<String> get reasoningText => _reasoning;

  /// The live speech transcript while [phase] is listening.
  ValueListenable<String> get liveTranscript => _live;

  /// Voice level `0..1` (mic while listening, voice while speaking).
  ValueListenable<double> get level => _level;

  /// Word index being spoken (for read-along highlighting).
  ValueListenable<int?> get spokenWord => _word;

  /// The orb state that matches [phase].
  NeuralOrbState get orbState => switch (_phase) {
        NeuralAgentPhase.listening => NeuralOrbState.listening,
        NeuralAgentPhase.thinking ||
        NeuralAgentPhase.usingTool =>
          NeuralOrbState.thinking,
        NeuralAgentPhase.responding ||
        NeuralAgentPhase.speaking =>
          NeuralOrbState.speaking,
        _ => NeuralOrbState.idle,
      };

  void _setV<T>(ValueNotifier<T> n, T v) {
    if (!_disposed) n.value = v;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setPhase(NeuralAgentPhase p) {
    if (_phase == p) return;
    _phase = p;
    _notify();
  }

  /// Sends a user message and runs the turn to completion.
  Future<void> send(String text,
      {List<NeuralImagePart> images = const []}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && images.isEmpty) return;
    if (isBusy) stop();
    _messages.add(NeuralMessage.user(trimmed, images: images));
    _notify();
    await _run();
  }

  /// Runs the model again from the current conversation (after an error,
  /// a refusal or a cancel).
  Future<void> retry() async {
    if (isBusy) return;
    // Drop a trailing partial assistant turn so the model answers afresh.
    while (
        _messages.isNotEmpty && _messages.last.role == NeuralRole.assistant) {
      _messages.removeLast();
    }
    if (_messages.isEmpty) return;
    await _run();
  }

  /// Sends a UI action (a button tap inside generated UI) back to the
  /// model as a user message.
  Future<void> sendAction(String action,
          [Map<String, Object?> data = const {}]) =>
      send(data.isEmpty
          ? action
          : '$action ${data.entries.map((e) => '${e.key}=${e.value}').join(', ')}');

  /// Clears the conversation.
  void clear() {
    stop();
    _messages.clear();
    _error = null;
    _lastFinish = null;
    _phase = NeuralAgentPhase.idle;
    _notify();
  }

  /// Stops generation, listening and speaking.
  void stop() {
    _cancel?.cancel();
    _cancel = null;
    _voiceSub?.cancel();
    _voiceSub = null;
    speechToText?.stop();
    textToSpeech?.stop();
    _setV(_level, 0.0);
    _setV(_word, null);
    _setV(_live, '');
    if (_phase != NeuralAgentPhase.error) _setPhase(NeuralAgentPhase.idle);
  }

  Future<void> _run() async {
    final cancel = _cancel = NeuralCancelToken();
    _error = null;
    for (var step = 0; step < maxSteps; step++) {
      if (cancel.isCancelled) return;
      _setPhase(NeuralAgentPhase.thinking);
      _setV(_streaming, '');
      _setV(_reasoning, '');
      final calls = <NeuralToolCall>[];
      NeuralFinishEvent? finish;
      final text = StringBuffer();
      final reasoning = StringBuffer();
      try {
        for (var attempt = 0;; attempt++) {
          try {
            final req = NeuralRequest(
              messages: List.unmodifiable(_messages),
              system: system,
              tools: tools,
              maxOutputTokens: maxOutputTokens,
              cancelToken: cancel,
            );
            await for (final e in _model.generate(req)) {
              if (cancel.isCancelled) break;
              switch (e) {
                case NeuralTextDelta():
                  if (_phase != NeuralAgentPhase.responding) {
                    _setPhase(NeuralAgentPhase.responding);
                  }
                  text.write(e.text);
                  _setV(_streaming, text.toString());
                case NeuralReasoningDelta():
                  reasoning.write(e.text);
                  _setV(_reasoning, reasoning.toString());
                case NeuralToolCallEvent():
                  calls.add(e.call);
                case NeuralUsageEvent():
                  _inputTokens += e.inputTokens;
                  _outputTokens += e.outputTokens;
                case NeuralFinishEvent():
                  finish = e;
              }
            }
            break;
          } on NeuralModelException catch (e) {
            // Retry only before anything reached the screen.
            final pristine = text.isEmpty && calls.isEmpty;
            if (!e.isRetryable ||
                !pristine ||
                attempt >= maxRetries ||
                cancel.isCancelled) {
              rethrow;
            }
            final wait = e.retryAfter ??
                Duration(milliseconds: (600 * math.pow(2, attempt)).round());
            await Future<void>.delayed(wait);
          }
        }
      } on Object catch (e) {
        if (cancel.isCancelled) return;
        _keepPartial(text.toString(), reasoning.toString());
        _error = e;
        _setV(_streaming, '');
        _setPhase(NeuralAgentPhase.error);
        return;
      }

      if (cancel.isCancelled) {
        _keepPartial(text.toString(), reasoning.toString());
        _setV(_streaming, '');
        return;
      }

      _lastFinish = finish;
      final assistant = NeuralMessage(
        role: NeuralRole.assistant,
        parts: [
          if (reasoning.isNotEmpty) NeuralReasoningPart(reasoning.toString()),
          if (text.isNotEmpty) NeuralTextPart(text.toString()),
          ...calls,
        ],
        providerContent: finish?.providerContent,
      );
      _messages.add(assistant);
      _setV(_streaming, '');
      _setV(_reasoning, '');
      _notify();

      final reason = finish?.reason ?? NeuralFinishReason.stop;
      if (reason == NeuralFinishReason.refusal ||
          reason == NeuralFinishReason.maxTokens ||
          calls.isEmpty) {
        break;
      }

      // Tools: run in call order, report every result in one message.
      _setPhase(NeuralAgentPhase.usingTool);
      final results = <NeuralToolResult>[];
      final uiParts = <NeuralUiPart>[];
      for (final call in calls) {
        if (cancel.isCancelled) return;
        _activeTool = call.name;
        _notify();
        final r = await _runTool(call);
        results.add(r);
        if (!r.isError &&
            uiCatalog != null &&
            call.name == uiCatalog!.toolName) {
          final spec = call.arguments['component'];
          if (spec is Map) {
            uiParts.add(NeuralUiPart(spec.map((k, v) => MapEntry('$k', v))));
          }
        }
      }
      _activeTool = null;
      if (uiParts.isNotEmpty) {
        final i = _messages.indexOf(assistant);
        _messages[i] =
            assistant.copyWith(parts: [...assistant.parts, ...uiParts]);
      }
      _messages.add(NeuralMessage(role: NeuralRole.tool, parts: results));
      _notify();
    }

    if (cancel.isCancelled) return;
    _cancel = null;
    final last = _messages.lastWhere(
      (m) => m.role == NeuralRole.assistant,
      orElse: () => NeuralMessage(role: NeuralRole.assistant, parts: const []),
    );
    if (speakReplies &&
        last.text.isNotEmpty &&
        (textToSpeech?.isAvailable ?? false)) {
      await speak(last.text);
    } else {
      _setPhase(NeuralAgentPhase.idle);
    }
  }

  void _keepPartial(String text, String reasoning) {
    if (text.isEmpty) return;
    _messages.add(NeuralMessage(
      role: NeuralRole.assistant,
      parts: [
        if (reasoning.isNotEmpty) NeuralReasoningPart(reasoning),
        NeuralTextPart(text),
      ],
    ));
  }

  Future<NeuralToolResult> _runTool(NeuralToolCall call) async {
    NeuralToolResult fail(String msg) => NeuralToolResult(
        callId: call.id, name: call.name, result: msg, isError: true);
    if (call.argumentsError != null) return fail(call.argumentsError!);
    final tool = tools.where((t) => t.name == call.name).firstOrNull;
    if (tool == null) return fail('Unknown tool "${call.name}".');
    final problems = tool.validate(call.arguments);
    if (problems.isNotEmpty) {
      return fail('Invalid arguments: ${problems.join('; ')}');
    }
    if (tool.requiresApproval) {
      final ok = await (onApproveTool?.call(call) ?? Future.value(false));
      if (!ok) return fail('The user declined to run ${call.name}.');
    }
    try {
      final out = await tool.handler(
          call.arguments, NeuralToolContext(callId: call.id));
      return NeuralToolResult(
          callId: call.id, name: call.name, result: out ?? 'ok');
    } on Object catch (e) {
      return fail('$e');
    }
  }

  /// Listens with [speechToText], then sends the final transcript.
  Future<void> listen() async {
    final stt = speechToText;
    if (stt == null || !stt.isAvailable) {
      _error = StateError('No speech-to-text engine available');
      _setPhase(NeuralAgentPhase.error);
      return;
    }
    // End any running turn or speech, but not the recognizer we are about
    // to start (stopping it asynchronously would race the new session).
    _cancel?.cancel();
    _cancel = null;
    _voiceSub?.cancel();
    _voiceSub = null;
    textToSpeech?.stop();
    _setPhase(NeuralAgentPhase.listening);
    _setV(_live, '');
    final done = Completer<String>();
    final levelSub = stt.levels.listen((l) => _setV(_level, l));
    _voiceSub = stt.listen(localeId: localeId).listen(
      (t) {
        _setV(_live, t.text);
        if (t.isFinal && !done.isCompleted) done.complete(t.text);
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(_live.value);
      },
    );
    try {
      final text = await done.future;
      await levelSub.cancel();
      _setV(_level, 0.0);
      _voiceSub = null;
      if (_phase != NeuralAgentPhase.listening) return; // stopped
      _setV(_live, '');
      if (text.trim().isEmpty) {
        _setPhase(NeuralAgentPhase.idle);
        return;
      }
      await send(text);
    } on Object catch (e) {
      await levelSub.cancel();
      _error = e;
      _setPhase(NeuralAgentPhase.error);
    }
  }

  /// Speaks [text] with [textToSpeech], driving [level] and [spokenWord].
  Future<void> speak(String text) async {
    final tts = textToSpeech;
    if (tts == null || !tts.isAvailable || text.trim().isEmpty) {
      _setPhase(NeuralAgentPhase.idle);
      return;
    }
    _setPhase(NeuralAgentPhase.speaking);
    final done = Completer<void>();
    _voiceSub = tts.speak(text, localeId: localeId).listen(
      (p) {
        _setV(_level, p.level);
        _setV(_word, p.wordIndex);
      },
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    _voiceSub = null;
    _setV(_level, 0.0);
    _setV(_word, null);
    if (_phase == NeuralAgentPhase.speaking) _setPhase(NeuralAgentPhase.idle);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _voiceSub?.cancel();
    _disposed = true;
    for (final n in [_streaming, _reasoning, _live, _level, _word]) {
      n.dispose();
    }
    super.dispose();
  }
}
