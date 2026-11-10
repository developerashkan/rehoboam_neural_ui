import 'dart:convert';

import 'package:http/http.dart' as http;

import '../neural_message.dart';
import '../neural_model.dart';

/// Any server that speaks the OpenAI Chat Completions streaming protocol:
/// OpenAI, Azure OpenAI-style gateways, OpenRouter, Groq, Together,
/// DeepSeek, Mistral, xAI, and local runtimes such as Ollama, LM Studio,
/// llama.cpp server and vLLM.
///
/// Use the named constructors for common hosts, or pass [baseUrl].
class OpenAICompatibleModel extends NeuralModel {
  /// Creates the adapter for an OpenAI-compatible [baseUrl] (ending in
  /// `/v1` or the provider's equivalent).
  OpenAICompatibleModel({
    required this.model,
    required this.baseUrl,
    this.apiKey,
    this.headers = const {},
    this.provider = 'openai',
    this.maxTokensField,
    this.extraBody = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// OpenAI (`https://api.openai.com/v1`).
  factory OpenAICompatibleModel.openAI({
    required String apiKey,
    required String model,
    http.Client? client,
  }) =>
      OpenAICompatibleModel(
        model: model,
        baseUrl: 'https://api.openai.com/v1',
        apiKey: apiKey,
        maxTokensField: 'max_completion_tokens',
        client: client,
      );

  /// OpenRouter: hundreds of models behind one key.
  factory OpenAICompatibleModel.openRouter({
    required String apiKey,
    required String model,
    http.Client? client,
  }) =>
      OpenAICompatibleModel(
        model: model,
        baseUrl: 'https://openrouter.ai/api/v1',
        apiKey: apiKey,
        provider: 'openrouter',
        client: client,
      );

  /// Groq.
  factory OpenAICompatibleModel.groq({
    required String apiKey,
    required String model,
    http.Client? client,
  }) =>
      OpenAICompatibleModel(
        model: model,
        baseUrl: 'https://api.groq.com/openai/v1',
        apiKey: apiKey,
        provider: 'groq',
        client: client,
      );

  /// Ollama running locally (on Android emulators use `10.0.2.2`).
  factory OpenAICompatibleModel.ollama({
    required String model,
    String baseUrl = 'http://localhost:11434/v1',
    http.Client? client,
  }) =>
      OpenAICompatibleModel(
        model: model,
        baseUrl: baseUrl,
        provider: 'ollama',
        client: client,
      );

  /// LM Studio's local server.
  factory OpenAICompatibleModel.lmStudio({
    required String model,
    String baseUrl = 'http://localhost:1234/v1',
    http.Client? client,
  }) =>
      OpenAICompatibleModel(
        model: model,
        baseUrl: baseUrl,
        provider: 'lmstudio',
        client: client,
      );

  /// Model id.
  final String model;

  /// API base URL.
  final String baseUrl;

  /// Bearer token. Prefer a proxy for production apps.
  final String? apiKey;

  /// Extra headers.
  final Map<String, String> headers;

  @override
  final String provider;

  /// Name of the output-limit field (`max_tokens` by default,
  /// `max_completion_tokens` for OpenAI).
  final String? maxTokensField;

  /// Extra body fields (provider-specific options).
  final Map<String, Object?> extraBody;

  final http.Client _client;

  /// Builds the JSON body.
  Map<String, Object?> buildBody(NeuralRequest r) => {
        'model': model,
        'stream': true,
        'stream_options': {'include_usage': true},
        if (r.maxOutputTokens != null)
          (maxTokensField ?? 'max_tokens'): r.maxOutputTokens,
        if (r.tools.isNotEmpty)
          'tools': [
            for (final t in r.tools)
              {
                'type': 'function',
                'function': {
                  'name': t.name,
                  'description': t.description,
                  'parameters': t.parameters,
                },
              },
          ],
        'messages': toWire(r.messages, r.system),
        ...extraBody,
      };

  /// Converts the conversation to Chat Completions messages.
  List<Map<String, Object?>> toWire(
      List<NeuralMessage> messages, String? system) {
    return [
      if (system != null && system.isNotEmpty)
        {'role': 'system', 'content': system},
      for (final m in messages)
        ...switch (m.role) {
          NeuralRole.user => [
              {
                'role': 'user',
                'content': m.parts.any((p) => p is NeuralImagePart)
                    ? [
                        for (final p in m.parts)
                          if (p is NeuralTextPart)
                            {'type': 'text', 'text': p.text}
                          else if (p is NeuralImagePart)
                            {
                              'type': 'image_url',
                              'image_url': {
                                'url': 'data:${p.mimeType};base64,${p.base64}'
                              },
                            },
                      ]
                    : m.text,
              },
            ],
          NeuralRole.assistant => [
              {
                'role': 'assistant',
                'content': m.text.isEmpty ? null : m.text,
                if (m.toolCalls.isNotEmpty)
                  'tool_calls': [
                    for (final c in m.toolCalls)
                      {
                        'id': c.id,
                        'type': 'function',
                        'function': {
                          'name': c.name,
                          'arguments': jsonEncode(c.arguments),
                        },
                      },
                  ],
              },
            ],
          NeuralRole.tool => [
              for (final r in m.parts.whereType<NeuralToolResult>())
                {
                  'role': 'tool',
                  'tool_call_id': r.callId,
                  'content': r.resultText
                },
            ],
        },
    ];
  }

  @override
  Stream<NeuralModelEvent> generate(NeuralRequest request) async* {
    final res = await postJsonStream(
      _client,
      Uri.parse('$baseUrl/chat/completions'),
      {
        if (apiKey != null) 'authorization': 'Bearer $apiKey',
        ...headers,
      },
      buildBody(request),
      cancel: request.cancelToken,
    );
    final ids = <int, String>{};
    final names = <int, String>{};
    final args = <int, StringBuffer>{};
    String? finish;
    var inTok = 0;
    var outTok = 0;
    await for (final e
        in parseSse(cancellable(res.stream, request.cancelToken))) {
      if (e.data == '[DONE]') break;
      if (e.data.isEmpty) continue;
      final Object? j;
      try {
        j = jsonDecode(e.data);
      } on FormatException {
        continue;
      }
      if (j is! Map) continue;
      if (j['error'] is Map) {
        throw NeuralModelException(
            (j['error'] as Map)['message'] as String? ?? 'error');
      }
      final usage = j['usage'];
      if (usage is Map) {
        inTok = (usage['prompt_tokens'] as num?)?.toInt() ?? inTok;
        outTok = (usage['completion_tokens'] as num?)?.toInt() ?? outTok;
      }
      final choices = j['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final c = choices.first as Map;
      finish = c['finish_reason'] as String? ?? finish;
      final d = c['delta'];
      if (d is! Map) continue;
      final text = d['content'];
      if (text is String && text.isNotEmpty) yield NeuralTextDelta(text);
      final reasoning = d['reasoning_content'] ?? d['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) {
        yield NeuralReasoningDelta(reasoning);
      }
      final tc = d['tool_calls'];
      if (tc is List) {
        for (final t in tc.whereType<Map>()) {
          final i = (t['index'] as num?)?.toInt() ?? 0;
          if (t['id'] is String) ids[i] = t['id'] as String;
          final f = t['function'];
          if (f is Map) {
            if (f['name'] is String) names[i] = '${names[i] ?? ''}${f['name']}';
            if (f['arguments'] is String) {
              (args[i] ??= StringBuffer()).write(f['arguments']);
            }
          }
        }
      }
    }
    if (request.cancelToken?.isCancelled ?? false) return;
    yield NeuralUsageEvent(inputTokens: inTok, outputTokens: outTok);
    if (finish == 'length') {
      yield const NeuralFinishEvent(NeuralFinishReason.maxTokens);
      return;
    }
    if (finish == 'content_filter') {
      yield const NeuralFinishEvent(NeuralFinishReason.refusal,
          detail: 'content_filter');
      return;
    }
    final keys = names.keys.toList()..sort();
    for (final i in keys) {
      final raw = args[i]?.toString() ?? '';
      final id = ids[i] ?? 'call_$i';
      try {
        yield NeuralToolCallEvent(NeuralToolCall(
            id: id, name: names[i]!, arguments: decodeArguments(raw)));
      } on FormatException catch (err) {
        yield NeuralToolCallEvent(NeuralToolCall(
            id: id,
            name: names[i]!,
            argumentsError: 'Invalid JSON arguments: ${err.message}'));
      }
    }
    yield NeuralFinishEvent(
      keys.isNotEmpty ? NeuralFinishReason.toolUse : NeuralFinishReason.stop,
      detail: finish,
    );
  }
}
