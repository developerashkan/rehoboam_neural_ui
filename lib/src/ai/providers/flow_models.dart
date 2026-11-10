import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../neural_message.dart';
import '../neural_model.dart';

/// A Genkit flow served over HTTP (`startFlowServer`, `expressHandler`, or
/// Genkit Go's handler). Streams the flow's chunks as text.
///
/// The flow owns its prompts, tools and model; this adapter sends the
/// conversation as the flow input. Tools passed to the agent are not
/// forwarded (define them inside the flow).
///
/// ```dart
/// GenkitFlowModel(
///   url: Uri.parse('https://api.example.com/chatFlow'),
///   headers: {'authorization': 'Bearer $idToken'},
/// )
/// ```
class GenkitFlowModel extends NeuralModel {
  /// Creates the adapter.
  GenkitFlowModel({
    required this.url,
    this.headers = const {},
    this.buildInput,
    this.chunkText,
    this.resultText,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// The flow endpoint (`POST {"data": input}`).
  final Uri url;

  /// Auth and other headers.
  final Map<String, String> headers;

  /// Maps the request to the flow input. Defaults to
  /// `{"prompt": lastUserText, "history": [{"role", "text"}...]}`.
  final Object? Function(NeuralRequest request)? buildInput;

  /// Extracts text from a streamed chunk. Defaults to the chunk itself if
  /// it is a string, or its `text` / `content` field.
  final String? Function(Object? chunk)? chunkText;

  /// Extracts text from the final result (used when nothing streamed).
  final String? Function(Object? result)? resultText;

  final http.Client _client;

  @override
  String get provider => 'genkit';

  /// The default flow input.
  static Object? defaultInput(NeuralRequest r) {
    final users = r.messages.where((m) => m.role == NeuralRole.user);
    return {
      'prompt': users.isEmpty ? '' : users.last.text,
      'history': [
        for (final m in r.messages)
          if (m.role != NeuralRole.tool && m.text.isNotEmpty)
            {
              'role': m.role == NeuralRole.user ? 'user' : 'model',
              'text': m.text
            },
      ],
      if (r.system != null) 'system': r.system,
    };
  }

  static String? _text(Object? v) {
    if (v is String) return v;
    if (v is Map) {
      for (final k in const ['text', 'content', 'output', 'answer']) {
        if (v[k] is String) return v[k] as String;
      }
    }
    return null;
  }

  @override
  Stream<NeuralModelEvent> generate(NeuralRequest request) async* {
    final streamUrl = url.replace(queryParameters: {
      ...url.queryParameters,
      'stream': 'true',
    });
    final res = await postJsonStream(
      _client,
      streamUrl,
      {'accept': 'text/event-stream', ...headers},
      {'data': (buildInput ?? defaultInput)(request)},
      cancel: request.cancelToken,
    );
    var streamed = false;
    await for (final e in parseSse(
      cancellable(res.stream, request.cancelToken),
      extraFields: const {'error'},
    )) {
      if (e.data.isEmpty) continue;
      final Object? j;
      try {
        j = jsonDecode(e.data);
      } on FormatException {
        continue;
      }
      if (j is! Map) continue;
      if (e.event == 'error' || j['error'] != null) {
        final err = j['error'];
        throw NeuralModelException(
          err is Map
              ? (err['message'] as String? ?? 'Flow error')
              : 'Flow error',
          statusCode: 500,
        );
      }
      if (j.containsKey('message')) {
        final t = (chunkText ?? _text)(j['message']);
        if (t != null && t.isNotEmpty) {
          streamed = true;
          yield NeuralTextDelta(t);
        }
      } else if (j.containsKey('result')) {
        if (!streamed) {
          final t = (resultText ?? _text)(j['result']) ??
              (j['result'] == null ? null : jsonEncode(j['result']));
          if (t != null && t.isNotEmpty) yield NeuralTextDelta(t);
        }
      }
    }
    if (request.cancelToken?.isCancelled ?? false) return;
    yield const NeuralFinishEvent(NeuralFinishReason.stop);
  }
}

/// Wraps any other SDK or on-device model (Firebase AI Logic,
/// flutter_gemma, a WebSocket...) in one function.
///
/// ```dart
/// CallbackModel.text((request) => myLlm.streamText(request.messages.last.text))
/// ```
class CallbackModel extends NeuralModel {
  /// Wraps a function that yields full [NeuralModelEvent]s (tool calls
  /// included). A missing [NeuralFinishEvent] is added for you.
  CallbackModel(this._generate, {this.provider = 'custom'});

  /// Wraps a function that only streams text.
  factory CallbackModel.text(
    Stream<String> Function(NeuralRequest request) stream, {
    String provider = 'custom',
  }) =>
      CallbackModel(
        (r) => stream(r).map<NeuralModelEvent>(NeuralTextDelta.new),
        provider: provider,
      );

  final Stream<NeuralModelEvent> Function(NeuralRequest request) _generate;

  @override
  final String provider;

  @override
  Stream<NeuralModelEvent> generate(NeuralRequest request) async* {
    var finished = false;
    await for (final e in _generate(request)) {
      if (request.cancelToken?.isCancelled ?? false) return;
      if (e is NeuralFinishEvent) finished = true;
      yield e;
    }
    if (!finished) yield const NeuralFinishEvent(NeuralFinishReason.stop);
  }
}

/// One scripted assistant turn for [ScriptedModel].
class ScriptedTurn {
  /// Creates a turn.
  const ScriptedTurn(
      {this.text = '', this.reasoning = '', this.toolCalls = const []});

  /// Answer text, streamed word by word.
  final String text;

  /// Reasoning summary, streamed first.
  final String reasoning;

  /// Tool calls to make after the text.
  final List<NeuralToolCall> toolCalls;
}

/// An offline model that plays back scripted turns: for demos, tests,
/// screenshots and UI development without a network or a key.
class ScriptedModel extends NeuralModel {
  /// Creates a model; [respond] picks the next turn from the request.
  ScriptedModel(
    this.respond, {
    this.wordDelay = const Duration(milliseconds: 45),
    this.thinkDelay = const Duration(milliseconds: 500),
  });

  /// Chooses the reply.
  final ScriptedTurn Function(NeuralRequest request) respond;

  /// Delay between streamed words.
  final Duration wordDelay;

  /// Pause before answering (shows the thinking state).
  final Duration thinkDelay;

  @override
  String get provider => 'scripted';

  @override
  Stream<NeuralModelEvent> generate(NeuralRequest request) async* {
    final turn = respond(request);
    bool cancelled() => request.cancelToken?.isCancelled ?? false;
    for (final w in _chunks(turn.reasoning)) {
      if (cancelled()) return;
      await Future<void>.delayed(wordDelay);
      yield NeuralReasoningDelta(w);
    }
    await Future<void>.delayed(thinkDelay);
    for (final w in _chunks(turn.text)) {
      if (cancelled()) return;
      await Future<void>.delayed(wordDelay);
      yield NeuralTextDelta(w);
    }
    if (cancelled()) return;
    for (final c in turn.toolCalls) {
      yield NeuralToolCallEvent(c);
    }
    yield NeuralUsageEvent(
      inputTokens: request.messages.length * 12,
      outputTokens: turn.text.length ~/ 4,
    );
    yield NeuralFinishEvent(turn.toolCalls.isEmpty
        ? NeuralFinishReason.stop
        : NeuralFinishReason.toolUse);
  }

  static Iterable<String> _chunks(String s) sync* {
    final re = RegExp(r'\S+\s*');
    for (final m in re.allMatches(s)) {
      yield m.group(0)!;
    }
  }
}

/// Encodes a value as pretty JSON (handy for tool results in UIs).
String prettyJson(Object? v) => const JsonEncoder.withIndent('  ').convert(v);
