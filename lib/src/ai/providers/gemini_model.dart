import 'dart:convert';

import 'package:http/http.dart' as http;

import '../neural_message.dart';
import '../neural_model.dart';

/// Google Gemini through the Generative Language API
/// (`streamGenerateContent?alt=sse`).
///
/// The model's parts, including any `thoughtSignature`, are replayed
/// exactly as received, which Gemini requires for function calling.
/// Sampling parameters are not sent (current Gemini models ignore them).
///
/// For production apps prefer Firebase AI Logic or your own backend; wrap
/// it with `CallbackModel`, or point [baseUrl] at a proxy.
class GeminiModel extends NeuralModel {
  /// Creates the adapter.
  GeminiModel({
    this.apiKey,
    this.model = 'gemini-3.8-flash',
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    this.showReasoning = true,
    this.headers = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// API key (`x-goog-api-key`).
  final String? apiKey;

  /// Model id.
  final String model;

  /// API base (or your proxy).
  final String baseUrl;

  /// Ask for thought summaries (`includeThoughts`).
  final bool showReasoning;

  /// Extra headers.
  final Map<String, String> headers;

  final http.Client _client;

  @override
  String get provider => 'google';

  /// Builds the JSON body.
  Map<String, Object?> buildBody(NeuralRequest r) => {
        'contents': toWire(r.messages),
        if (r.system != null && r.system!.isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': r.system},
            ],
          },
        if (r.tools.isNotEmpty)
          'tools': [
            {
              'functionDeclarations': [
                for (final t in r.tools)
                  {
                    'name': t.name,
                    'description': t.description,
                    'parametersJsonSchema': t.parameters,
                  },
              ],
            },
          ],
        'generationConfig': {
          if (r.maxOutputTokens != null) 'maxOutputTokens': r.maxOutputTokens,
          if (showReasoning) 'thinkingConfig': {'includeThoughts': true},
        },
      };

  /// Converts the conversation to `contents`.
  List<Map<String, Object?>> toWire(List<NeuralMessage> messages) {
    final out = <Map<String, Object?>>[];
    for (final m in messages) {
      switch (m.role) {
        case NeuralRole.user:
          out.add({
            'role': 'user',
            'parts': [
              for (final p in m.parts)
                if (p is NeuralImagePart)
                  {
                    'inlineData': {'mimeType': p.mimeType, 'data': p.base64},
                  }
                else if (p is NeuralTextPart)
                  {'text': p.text},
            ],
          });
        case NeuralRole.assistant:
          final native = m.providerContent?[provider];
          out.add({
            'role': 'model',
            'parts': native is List
                ? native
                : [
                    for (final p in m.parts)
                      if (p is NeuralTextPart)
                        {'text': p.text}
                      else if (p is NeuralToolCall)
                        {
                          'functionCall': {
                            'id': p.id,
                            'name': p.name,
                            'args': p.arguments,
                          },
                        },
                  ],
          });
        case NeuralRole.tool:
          // All responses together, in call order, after the calls.
          out.add({
            'role': 'user',
            'parts': [
              for (final r in m.parts.whereType<NeuralToolResult>())
                {
                  'functionResponse': {
                    'id': r.callId,
                    'name': r.name,
                    'response': r.isError
                        ? {'error': r.resultText}
                        : (r.result is Map ? r.result : {'result': r.result}),
                  },
                },
            ],
          });
      }
    }
    return out;
  }

  @override
  Stream<NeuralModelEvent> generate(NeuralRequest request) async* {
    final res = await postJsonStream(
      _client,
      Uri.parse('$baseUrl/models/$model:streamGenerateContent?alt=sse'),
      {
        if (apiKey != null) 'x-goog-api-key': apiKey!,
        ...headers,
      },
      buildBody(request),
      cancel: request.cancelToken,
    );
    final parts = <Object?>[];
    final calls = <NeuralToolCall>[];
    String? finish;
    var inTok = 0;
    var outTok = 0;
    await for (final e
        in parseSse(cancellable(res.stream, request.cancelToken))) {
      if (e.data.isEmpty) continue;
      final Object? j;
      try {
        j = jsonDecode(e.data);
      } on FormatException {
        continue;
      }
      if (j is! Map) continue;
      if (j['error'] is Map) {
        final err = j['error'] as Map;
        throw NeuralModelException(err['message'] as String? ?? 'error',
            statusCode: (err['code'] as num?)?.toInt());
      }
      final usage = j['usageMetadata'];
      if (usage is Map) {
        inTok = (usage['promptTokenCount'] as num?)?.toInt() ?? inTok;
        outTok = (usage['candidatesTokenCount'] as num?)?.toInt() ?? outTok;
      }
      final cands = j['candidates'];
      if (cands is! List || cands.isEmpty) continue;
      final c = cands.first as Map;
      finish = c['finishReason'] as String? ?? finish;
      final content = c['content'];
      if (content is! Map) continue;
      final ps = content['parts'];
      if (ps is! List) continue;
      for (final p in ps.whereType<Map>()) {
        parts.add(p); // verbatim, signatures included
        final text = p['text'];
        if (text is String && text.isNotEmpty) {
          yield p['thought'] == true
              ? NeuralReasoningDelta(text)
              : NeuralTextDelta(text);
        }
        final fc = p['functionCall'];
        if (fc is Map) {
          final a = fc['args'];
          calls.add(NeuralToolCall(
            id: fc['id'] as String? ?? 'call_${calls.length}',
            name: fc['name'] as String? ?? '',
            arguments: a is Map ? a.map((k, v) => MapEntry('$k', v)) : {},
          ));
        }
      }
    }
    if (request.cancelToken?.isCancelled ?? false) return;
    yield NeuralUsageEvent(inputTokens: inTok, outputTokens: outTok);
    final native = {provider: parts};
    switch (finish) {
      case 'MAX_TOKENS':
        yield NeuralFinishEvent(NeuralFinishReason.maxTokens,
            providerContent: native, detail: finish);
        return;
      case 'SAFETY' ||
            'RECITATION' ||
            'PROHIBITED_CONTENT' ||
            'BLOCKLIST' ||
            'SPII':
        yield NeuralFinishEvent(NeuralFinishReason.refusal,
            providerContent: native, detail: finish);
        return;
    }
    for (final c in calls) {
      yield NeuralToolCallEvent(c);
    }
    yield NeuralFinishEvent(
      calls.isNotEmpty
          ? NeuralFinishReason.toolUse
          : finish == null || finish == 'STOP'
              ? NeuralFinishReason.stop
              : NeuralFinishReason.other,
      providerContent: native,
      detail: finish,
    );
  }
}
