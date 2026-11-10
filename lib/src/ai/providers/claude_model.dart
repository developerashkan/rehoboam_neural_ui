import 'dart:convert';

import 'package:http/http.dart' as http;

import '../neural_message.dart';
import '../neural_model.dart';

/// Claude, through the Anthropic Messages API (streamed over SSE).
///
/// Defaults follow Anthropic's current guidance: `claude-opus-5-5`,
/// adaptive thinking with summarized reasoning (shown as "thinking"),
/// streaming, eager tool-input streaming with strict client-side parsing,
/// and server-side refusal fallbacks (`fallbacks: "default"`), which you
/// can turn off with [fallbacks].
///
/// Thinking blocks are replayed unchanged on the next request, as the API
/// requires for multi-step tool use.
///
/// Do not ship a secret API key inside an app. Point [baseUrl] at your own
/// proxy and pass its auth in [headers] instead (leave [apiKey] `null`).
class ClaudeModel extends NeuralModel {
  /// Creates the adapter.
  ClaudeModel({
    this.apiKey,
    this.model = 'claude-opus-5-5',
    this.baseUrl = 'https://api.anthropic.com',
    this.maxTokens = 64000,
    this.effort,
    this.showReasoning = true,
    this.fallbacks = true,
    this.browserAccess = false,
    this.headers = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// API key (`x-api-key`). Prefer a proxy in production.
  final String? apiKey;

  /// Model id.
  final String model;

  /// API origin (or your proxy).
  final String baseUrl;

  /// `max_tokens` when the request does not set one.
  final int maxTokens;

  /// `output_config.effort`: `low`, `medium`, `high`, `xhigh` or `max`.
  /// `null` uses the model default (`medium` on Claude Opus 5.5).
  final String? effort;

  /// Stream reasoning summaries (`thinking.display: "summarized"`).
  final bool showReasoning;

  /// Send `fallbacks: "default"` so a policy refusal is retried on a
  /// fallback model inside the same call.
  final bool fallbacks;

  /// Allow direct calls from a browser (sends
  /// `anthropic-dangerous-direct-browser-access`). Only for prototypes.
  final bool browserAccess;

  /// Extra headers (proxy auth, tracing...).
  final Map<String, String> headers;

  final http.Client _client;

  @override
  String get provider => 'anthropic';

  /// Builds the JSON body (exposed for tests and logging).
  Map<String, Object?> buildBody(NeuralRequest r) => {
        'model': model,
        'max_tokens': r.maxOutputTokens ?? maxTokens,
        'stream': true,
        if (r.system != null && r.system!.isNotEmpty) 'system': r.system,
        'thinking': {
          'type': 'adaptive',
          if (showReasoning) 'display': 'summarized',
        },
        if (effort != null) 'output_config': {'effort': effort},
        if (fallbacks) 'fallbacks': 'default',
        if (r.tools.isNotEmpty)
          'tools': [
            for (final t in r.tools)
              {
                'name': t.name,
                'description': t.description,
                'input_schema': t.parameters,
                'eager_input_streaming': true,
              },
          ],
        'messages': toWire(r.messages),
      };

  /// Converts the conversation to Messages API form.
  List<Map<String, Object?>> toWire(List<NeuralMessage> messages) {
    final out = <Map<String, Object?>>[];
    void add(String role, List<Object?> content) {
      if (content.isEmpty) return;
      if (out.isNotEmpty && out.last['role'] == role) {
        final prev = (out.last['content'] as List).cast<Object?>();
        // tool_result blocks must lead a user turn.
        final results = [
          ...prev.where(_isResult),
          ...content.where(_isResult),
        ];
        final rest = [
          ...prev.where((b) => !_isResult(b)),
          ...content.where((b) => !_isResult(b)),
        ];
        out.last['content'] = [...results, ...rest];
      } else {
        out.add({'role': role, 'content': content});
      }
    }

    for (final m in messages) {
      switch (m.role) {
        case NeuralRole.user:
          add('user', [
            for (final p in m.parts)
              if (p is NeuralImagePart)
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': p.mimeType,
                    'data': p.base64,
                  },
                }
              else if (p is NeuralTextPart && p.text.isNotEmpty)
                {'type': 'text', 'text': p.text},
          ]);
        case NeuralRole.tool:
          add('user', [
            for (final p in m.parts.whereType<NeuralToolResult>())
              {
                'type': 'tool_result',
                'tool_use_id': p.callId,
                'content': p.resultText,
                if (p.isError) 'is_error': true,
              },
          ]);
        case NeuralRole.assistant:
          final native = m.providerContent?[provider];
          if (native is List) {
            add('assistant', native.cast<Object?>());
          } else {
            add('assistant', [
              for (final p in m.parts)
                if (p is NeuralTextPart && p.text.isNotEmpty)
                  {'type': 'text', 'text': p.text}
                else if (p is NeuralToolCall)
                  {
                    'type': 'tool_use',
                    'id': p.id,
                    'name': p.name,
                    'input': p.arguments,
                  },
            ]);
          }
      }
    }
    return out;
  }

  static bool _isResult(Object? b) => b is Map && b['type'] == 'tool_result';

  @override
  Stream<NeuralModelEvent> generate(NeuralRequest request) async* {
    final res = await postJsonStream(
      _client,
      Uri.parse('$baseUrl/v1/messages'),
      {
        'anthropic-version': '2026-10-21',
        if (apiKey != null) 'x-api-key': apiKey!,
        if (fallbacks) 'anthropic-beta': 'server-side-fallback-2026-07-01',
        if (browserAccess) 'anthropic-dangerous-direct-browser-access': 'true',
        ...headers,
      },
      buildBody(request),
      cancel: request.cancelToken,
    );

    final blocks = <int, Map<String, Object?>>{};
    final rawJson = <int, StringBuffer>{};
    final calls = <NeuralToolCall>[];
    String? stopReason;
    String? stopDetail;
    var inputTokens = 0;
    var outputTokens = 0;

    await for (final e
        in parseSse(cancellable(res.stream, request.cancelToken))) {
      if (e.data.isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(e.data);
      } on FormatException {
        continue;
      }
      if (decoded is! Map) continue;
      final j = decoded.cast<String, Object?>();
      switch (j['type']) {
        case 'message_start':
          final u = (j['message'] as Map?)?['usage'];
          if (u is Map) inputTokens = (u['input_tokens'] as num?)?.toInt() ?? 0;
        case 'content_block_start':
          final i = (j['index'] as num).toInt();
          final b = Map<String, Object?>.from(j['content_block'] as Map);
          if (b['type'] == 'tool_use') {
            b['input'] = <String, Object?>{};
            rawJson[i] = StringBuffer();
          }
          blocks[i] = b;
        case 'content_block_delta':
          final i = (j['index'] as num).toInt();
          final d = (j['delta'] as Map).cast<String, Object?>();
          final b = blocks[i];
          if (b == null) continue;
          switch (d['type']) {
            case 'text_delta':
              final t = d['text'] as String? ?? '';
              b['text'] = '${b['text'] ?? ''}$t';
              if (t.isNotEmpty) yield NeuralTextDelta(t);
            case 'thinking_delta':
              final t = d['thinking'] as String? ?? '';
              b['thinking'] = '${b['thinking'] ?? ''}$t';
              if (t.isNotEmpty) yield NeuralReasoningDelta(t);
            case 'signature_delta':
              b['signature'] = '${b['signature'] ?? ''}${d['signature'] ?? ''}';
            case 'input_json_delta':
              rawJson[i]?.write(d['partial_json'] ?? '');
          }
        case 'content_block_stop':
          final i = (j['index'] as num).toInt();
          final b = blocks[i];
          if (b != null && b['type'] == 'tool_use') {
            final raw = rawJson[i]?.toString() ?? '';
            try {
              final args = decodeArguments(raw);
              b['input'] = args;
              calls.add(NeuralToolCall(
                id: b['id'] as String? ?? '',
                name: b['name'] as String? ?? '',
                arguments: args,
              ));
            } on FormatException catch (err) {
              calls.add(NeuralToolCall(
                id: b['id'] as String? ?? '',
                name: b['name'] as String? ?? '',
                argumentsError: 'Invalid JSON arguments: ${err.message}',
              ));
            }
          }
        case 'message_delta':
          final d = j['delta'];
          if (d is Map) {
            stopReason = d['stop_reason'] as String? ?? stopReason;
            final sd = d['stop_details'];
            if (sd is Map) stopDetail = sd['category'] as String?;
          }
          final u = j['usage'];
          if (u is Map) {
            outputTokens =
                (u['output_tokens'] as num?)?.toInt() ?? outputTokens;
          }
        case 'error':
          final err = (j['error'] as Map?)?.cast<String, Object?>() ?? {};
          final type = err['type'] as String? ?? 'error';
          throw NeuralModelException(
            err['message'] as String? ?? type,
            statusCode: type == 'overloaded_error'
                ? 529
                : type == 'rate_limit_error'
                    ? 429
                    : type == 'api_error'
                        ? 500
                        : 400,
          );
      }
    }
    if (request.cancelToken?.isCancelled ?? false) return;

    yield NeuralUsageEvent(
        inputTokens: inputTokens, outputTokens: outputTokens);
    final ordered =
        (blocks.keys.toList()..sort()).map((k) => blocks[k]!).toList();
    final native = {provider: ordered};

    // Never run tools from a refused or truncated turn.
    if (stopReason == 'refusal') {
      yield NeuralFinishEvent(NeuralFinishReason.refusal,
          providerContent: native, detail: stopDetail);
      return;
    }
    if (stopReason == 'max_tokens') {
      yield NeuralFinishEvent(NeuralFinishReason.maxTokens,
          providerContent: native, detail: stopReason);
      return;
    }
    for (final c in calls) {
      yield NeuralToolCallEvent(c);
    }
    yield NeuralFinishEvent(
      stopReason == 'tool_use'
          ? NeuralFinishReason.toolUse
          : stopReason == 'end_turn' || stopReason == 'stop_sequence'
              ? NeuralFinishReason.stop
              : NeuralFinishReason.other,
      providerContent: native,
      detail: stopReason,
    );
  }
}
