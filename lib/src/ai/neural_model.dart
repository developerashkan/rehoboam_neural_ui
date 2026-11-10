import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'neural_message.dart';
import 'neural_tool.dart';

/// Something a model emits while generating.
@immutable
sealed class NeuralModelEvent {
  const NeuralModelEvent();
}

/// More answer text.
class NeuralTextDelta extends NeuralModelEvent {
  /// Creates a delta.
  const NeuralTextDelta(this.text);

  /// The new text.
  final String text;
}

/// More reasoning summary text (shown as "thinking").
class NeuralReasoningDelta extends NeuralModelEvent {
  /// Creates a delta.
  const NeuralReasoningDelta(this.text);

  /// The new text.
  final String text;
}

/// The model wants a tool run. Arguments are complete and parsed.
class NeuralToolCallEvent extends NeuralModelEvent {
  /// Creates the event.
  const NeuralToolCallEvent(this.call);

  /// The call.
  final NeuralToolCall call;
}

/// Token accounting.
class NeuralUsageEvent extends NeuralModelEvent {
  /// Creates the event.
  const NeuralUsageEvent({this.inputTokens = 0, this.outputTokens = 0});

  /// Prompt tokens.
  final int inputTokens;

  /// Generated tokens.
  final int outputTokens;
}

/// Why generation stopped.
enum NeuralFinishReason {
  /// Natural end of the answer.
  stop,

  /// The model is waiting for tool results.
  toolUse,

  /// Hit the output limit.
  maxTokens,

  /// The provider declined (safety / policy).
  refusal,

  /// Anything else the provider reported.
  other,
}

/// The final event of a generation.
class NeuralFinishEvent extends NeuralModelEvent {
  /// Creates the event.
  const NeuralFinishEvent(this.reason, {this.providerContent, this.detail});

  /// Why it stopped.
  final NeuralFinishReason reason;

  /// The provider's own wire form of the assistant turn, replayed verbatim
  /// on the next request (thinking / thought signatures). Keyed by provider.
  final Map<String, Object?>? providerContent;

  /// Provider detail (raw stop reason, refusal category...).
  final String? detail;
}

/// Lets the app stop a generation.
class NeuralCancelToken {
  final Completer<void> _c = Completer<void>();

  /// Requests cancellation.
  void cancel() {
    if (!_c.isCompleted) _c.complete();
  }

  /// Whether [cancel] was called.
  bool get isCancelled => _c.isCompleted;

  /// Completes when cancelled.
  Future<void> get whenCancelled => _c.future;
}

/// A request to a [NeuralModel].
@immutable
class NeuralRequest {
  /// Creates a request.
  const NeuralRequest({
    required this.messages,
    this.system,
    this.tools = const [],
    this.maxOutputTokens,
    this.cancelToken,
  });

  /// The conversation so far (oldest first).
  final List<NeuralMessage> messages;

  /// System instructions.
  final String? system;

  /// Tools the model may call.
  final List<NeuralTool> tools;

  /// Output token cap (provider default when `null`).
  final int? maxOutputTokens;

  /// Cancellation.
  final NeuralCancelToken? cancelToken;
}

/// A provider failure with an HTTP status when there is one.
class NeuralModelException implements Exception {
  /// Creates the exception.
  const NeuralModelException(this.message, {this.statusCode, this.retryAfter});

  /// Human readable message.
  final String message;

  /// HTTP status, if any.
  final int? statusCode;

  /// Server-suggested wait before retrying.
  final Duration? retryAfter;

  /// Whether retrying can help (rate limits, overload, network).
  bool get isRetryable =>
      statusCode == null ||
      statusCode == 408 ||
      statusCode == 409 ||
      statusCode == 429 ||
      (statusCode != null && statusCode! >= 500);

  @override
  String toString() =>
      'NeuralModelException(${statusCode ?? 'network'}): $message';
}

/// Any LLM, local or remote. Implement [generate] to plug in a provider
/// this package does not ship (or wrap an SDK with `CallbackModel`).
abstract class NeuralModel {
  /// Const constructor for subclasses.
  const NeuralModel();

  /// Short provider id, also the key for [NeuralMessage.providerContent].
  String get provider;

  /// Streams the assistant's next turn. Must end with exactly one
  /// [NeuralFinishEvent] unless an error is thrown or the request is
  /// cancelled.
  Stream<NeuralModelEvent> generate(NeuralRequest request);
}

/// One Server-Sent Event.
@immutable
class SseEvent {
  /// Creates an event.
  const SseEvent({this.event, required this.data});

  /// The `event:` field, if any.
  final String? event;

  /// The joined `data:` lines.
  final String data;
}

/// Parses a byte stream of Server-Sent Events. Handles CRLF / LF line
/// endings, multi-line `data:`, comments and a final unterminated event.
///
/// [extraFields] lets non-standard servers (Genkit's `error:` lines) be
/// treated as events named after the field.
Stream<SseEvent> parseSse(
  Stream<List<int>> bytes, {
  Set<String> extraFields = const {},
}) async* {
  String? event;
  final data = <String>[];
  var buffer = '';
  SseEvent? flush() {
    if (data.isEmpty && event == null) return null;
    final e = SseEvent(event: event, data: data.join('\n'));
    event = null;
    data.clear();
    return e;
  }

  Iterable<SseEvent> lines(String chunk, {bool last = false}) sync* {
    buffer += chunk;
    while (true) {
      final i = buffer.indexOf('\n');
      if (i < 0) break;
      var line = buffer.substring(0, i);
      buffer = buffer.substring(i + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.isEmpty) {
        final e = flush();
        if (e != null) yield e;
        continue;
      }
      if (line.startsWith(':')) continue;
      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      if (field == 'data') {
        data.add(value);
      } else if (field == 'event') {
        event = value;
      } else if (extraFields.contains(field)) {
        event = field;
        data.add(value);
      }
    }
    if (last) {
      if (buffer.isNotEmpty) {
        buffer += '\n';
        yield* lines('');
      }
      final e = flush();
      if (e != null) yield e;
    }
  }

  await for (final chunk in utf8.decoder.bind(bytes)) {
    yield* Stream.fromIterable(lines(chunk));
  }
  yield* Stream.fromIterable(lines('', last: true));
}

/// Posts [body] as JSON and returns the streamed response, throwing
/// [NeuralModelException] for non-2xx statuses. Cancelling [cancel]
/// closes the connection.
Future<http.StreamedResponse> postJsonStream(
  http.Client client,
  Uri url,
  Map<String, String> headers,
  Object body, {
  NeuralCancelToken? cancel,
}) async {
  final req = http.Request('POST', url)
    ..headers.addAll({'content-type': 'application/json', ...headers})
    ..body = jsonEncode(body);
  http.StreamedResponse res;
  try {
    res = await client.send(req);
  } on http.ClientException catch (e) {
    throw NeuralModelException(e.message);
  }
  if (res.statusCode < 200 || res.statusCode >= 300) {
    final text = await res.stream.bytesToString();
    final ra = int.tryParse(res.headers['retry-after'] ?? '');
    throw NeuralModelException(
      _errorMessage(text) ?? 'HTTP ${res.statusCode}',
      statusCode: res.statusCode,
      retryAfter: ra == null ? null : Duration(seconds: ra),
    );
  }
  return res;
}

String? _errorMessage(String body) {
  try {
    final j = jsonDecode(body);
    if (j is Map) {
      final e = j['error'];
      if (e is Map && e['message'] is String) return e['message'] as String;
      if (e is String) return e;
      if (j['message'] is String) return j['message'] as String;
    }
    if (j is List && j.isNotEmpty && j.first is Map) {
      final e = (j.first as Map)['error'];
      if (e is Map && e['message'] is String) return e['message'] as String;
    }
  } on FormatException {
    // not JSON
  }
  return body.isEmpty
      ? null
      : body.length > 300
          ? body.substring(0, 300)
          : body;
}

/// Wraps a response body stream so cancellation stops reading.
Stream<List<int>> cancellable(Stream<List<int>> s, NeuralCancelToken? token) {
  if (token == null) return s;
  final controller = StreamController<List<int>>();
  late StreamSubscription<List<int>> sub;
  controller.onListen = () {
    sub = s.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    token.whenCancelled.then((_) {
      sub.cancel();
      if (!controller.isClosed) controller.close();
    });
  };
  controller.onCancel = () => sub.cancel();
  return controller.stream;
}

/// Strictly decodes JSON tool arguments; throws [FormatException].
Map<String, Object?> decodeArguments(String raw) {
  if (raw.trim().isEmpty) return {};
  final v = jsonDecode(raw);
  if (v is! Map) {
    throw const FormatException('Tool arguments must be an object');
  }
  return v.map((k, v) => MapEntry('$k', v));
}
