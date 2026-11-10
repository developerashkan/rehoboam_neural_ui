import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';

import 'helpers.dart';

/// A mock client that streams [chunks] as the response body and records
/// the request.
MockClient sse(List<String> chunks,
        {int status = 200,
        void Function(http.BaseRequest, String)? onRequest}) =>
    MockClient.streaming((req, body) async {
      onRequest?.call(req, await body.bytesToString());
      return http.StreamedResponse(
        Stream.fromIterable(chunks.map(utf8.encode)),
        status,
        headers: {'content-type': 'text/event-stream'},
      );
    });

String ev(Map<String, Object?> j, {String? event}) =>
    '${event != null ? 'event: $event\n' : ''}data: ${jsonEncode(j)}\n\n';

Future<List<NeuralModelEvent>> collect(NeuralModel m, NeuralRequest r) =>
    m.generate(r).toList();

final _weather = NeuralTool(
  name: 'get_weather',
  description: 'Weather for a city',
  parameters: const {
    'type': 'object',
    'properties': {
      'city': {'type': 'string'},
    },
    'required': ['city'],
  },
  handler: (args, ctx) => {'city': args['city'], 'tempC': 21},
);

void main() {
  group('SSE parser', () {
    test('handles CRLF, multi-line data, comments and split chunks', () async {
      final bytes = Stream.fromIterable([
        ': keep-alive\r\n',
        'event: a\r\ndata: one\r\n',
        'data: two\r\n\r\nda',
        'ta: {"x":1}\n\n',
        'data: tail-without-blank-line',
      ].map(utf8.encode));
      final events = await parseSse(bytes).toList();
      expect(events.map((e) => e.data),
          ['one\ntwo', '{"x":1}', 'tail-without-blank-line']);
      expect(events.first.event, 'a');
    });

    test('extra fields become events', () async {
      final events = await parseSse(
        Stream.value(utf8.encode('error: {"error":{"message":"boom"}}\n\n')),
        extraFields: const {'error'},
      ).toList();
      expect(events.single.event, 'error');
    });
  });

  group('ClaudeModel', () {
    test('request body follows current API guidance', () async {
      late Map<String, Object?> body;
      late Map<String, String> headers;
      final m = ClaudeModel(
        apiKey: 'k',
        client: sse([
          ev({'type': 'message_stop'})
        ], onRequest: (r, b) {
          body = jsonDecode(b) as Map<String, Object?>;
          headers = r.headers;
        }),
      );
      await collect(
          m,
          NeuralRequest(
            messages: [NeuralMessage.user('hi')],
            system: 'Be brief',
            tools: [_weather],
          ));
      expect(body['model'], 'claude-opus-5-5');
      expect(body['stream'], true);
      expect(body['thinking'], {'type': 'adaptive', 'display': 'summarized'});
      expect(body['fallbacks'], 'default');
      expect(body.containsKey('temperature'), isFalse);
      final tool = (body['tools'] as List).single as Map;
      expect(tool['eager_input_streaming'], true);
      expect(tool['input_schema'], _weather.parameters);
      expect(headers['anthropic-version'], '2026-10-21');
      expect(headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
      expect(headers['x-api-key'], 'k');
    });

    test('streams text, reasoning and a tool call; keeps signed thinking',
        () async {
      final m = ClaudeModel(
          apiKey: 'k',
          client: sse([
            ev({
              'type': 'message_start',
              'message': {
                'usage': {'input_tokens': 12}
              }
            }),
            ev({
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'thinking', 'thinking': ''}
            }),
            ev({
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'thinking_delta', 'thinking': 'Need weather.'}
            }),
            ev({
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'signature_delta', 'signature': 'SIG'}
            }),
            ev({'type': 'content_block_stop', 'index': 0}),
            ev({
              'type': 'content_block_start',
              'index': 1,
              'content_block': {'type': 'text', 'text': ''}
            }),
            ev({
              'type': 'content_block_delta',
              'index': 1,
              'delta': {'type': 'text_delta', 'text': 'Checking'}
            }),
            ev({'type': 'content_block_stop', 'index': 1}),
            ev({
              'type': 'content_block_start',
              'index': 2,
              'content_block': {
                'type': 'tool_use',
                'id': 'tu1',
                'name': 'get_weather',
                'input': {}
              }
            }),
            ev({
              'type': 'content_block_delta',
              'index': 2,
              'delta': {'type': 'input_json_delta', 'partial_json': '{"ci'}
            }),
            ev({
              'type': 'content_block_delta',
              'index': 2,
              'delta': {
                'type': 'input_json_delta',
                'partial_json': 'ty":"Oslo"}'
              }
            }),
            ev({'type': 'content_block_stop', 'index': 2}),
            ev({
              'type': 'message_delta',
              'delta': {'stop_reason': 'tool_use'},
              'usage': {'output_tokens': 30}
            }),
            ev({'type': 'message_stop'}),
          ]));
      final events =
          await collect(m, NeuralRequest(messages: [NeuralMessage.user('w?')]));
      expect(events.whereType<NeuralReasoningDelta>().single.text,
          'Need weather.');
      expect(events.whereType<NeuralTextDelta>().single.text, 'Checking');
      final call = events.whereType<NeuralToolCallEvent>().single.call;
      expect(call.arguments, {'city': 'Oslo'});
      final fin = events.last as NeuralFinishEvent;
      expect(fin.reason, NeuralFinishReason.toolUse);
      final blocks = fin.providerContent!['anthropic']! as List;
      expect((blocks[0] as Map)['signature'], 'SIG');
      expect((blocks[2] as Map)['input'], {'city': 'Oslo'});

      // Replayed verbatim on the next request.
      final assistant = NeuralMessage(
        role: NeuralRole.assistant,
        parts: [const NeuralTextPart('Checking'), call],
        providerContent: fin.providerContent,
      );
      final wire = m.toWire([
        NeuralMessage.user('w?'),
        assistant,
        NeuralMessage(role: NeuralRole.tool, parts: [
          const NeuralToolResult(
              callId: 'tu1', name: 'get_weather', result: {'t': 1}),
        ]),
      ]);
      expect(wire[1]['content'], blocks);
      expect(
          ((wire[2]['content'] as List).single as Map)['tool_use_id'], 'tu1');
    });

    test('refusal and max_tokens never yield tool calls', () async {
      for (final reason in ['refusal', 'max_tokens']) {
        final m = ClaudeModel(
            apiKey: 'k',
            client: sse([
              ev({
                'type': 'content_block_start',
                'index': 0,
                'content_block': {
                  'type': 'tool_use',
                  'id': 't',
                  'name': 'get_weather',
                  'input': {}
                }
              }),
              ev({
                'type': 'content_block_delta',
                'index': 0,
                'delta': {
                  'type': 'input_json_delta',
                  'partial_json': '{"city":"Os'
                }
              }),
              ev({'type': 'content_block_stop', 'index': 0}),
              ev({
                'type': 'message_delta',
                'delta': {'stop_reason': reason}
              }),
            ]));
        final events = await collect(
            m, NeuralRequest(messages: [NeuralMessage.user('x')]));
        expect(events.whereType<NeuralToolCallEvent>(), isEmpty,
            reason: reason);
        expect(
            (events.last as NeuralFinishEvent).reason,
            reason == 'refusal'
                ? NeuralFinishReason.refusal
                : NeuralFinishReason.maxTokens);
      }
    });

    test('HTTP errors carry status and retry-after', () async {
      final m = ClaudeModel(
        apiKey: 'k',
        client: MockClient((r) async => http.Response(
            jsonEncode({
              'error': {'type': 'rate_limit_error', 'message': 'slow down'}
            }),
            429,
            headers: {'retry-after': '3'})),
      );
      await expectLater(
        collect(m, NeuralRequest(messages: [NeuralMessage.user('x')])),
        throwsA(isA<NeuralModelException>()
            .having((e) => e.statusCode, 'status', 429)
            .having((e) => e.isRetryable, 'retryable', true)
            .having(
                (e) => e.retryAfter, 'retryAfter', const Duration(seconds: 3))
            .having((e) => e.message, 'message', 'slow down')),
      );
    });
  });

  group('OpenAICompatibleModel', () {
    test('assembles streamed tool-call fragments', () async {
      late Map<String, Object?> body;
      final m = OpenAICompatibleModel.ollama(
        model: 'llama4',
        client: sse([
          ev({
            'choices': [
              {
                'delta': {'content': 'Hi '}
              }
            ]
          }),
          ev({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'c1',
                      'function': {
                        'name': 'get_weather',
                        'arguments': '{"city":'
                      }
                    }
                  ]
                }
              }
            ]
          }),
          ev({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': '"Rome"}'}
                    }
                  ]
                },
                'finish_reason': 'tool_calls'
              }
            ]
          }),
          ev({
            'choices': [],
            'usage': {'prompt_tokens': 5, 'completion_tokens': 7}
          }),
          'data: [DONE]\n\n',
        ], onRequest: (r, b) => body = jsonDecode(b) as Map<String, Object?>),
      );
      final events = await collect(
          m,
          NeuralRequest(
              messages: [NeuralMessage.user('w')],
              system: 'S',
              tools: [_weather]));
      expect(events.whereType<NeuralToolCallEvent>().single.call.arguments,
          {'city': 'Rome'});
      expect((events.last as NeuralFinishEvent).reason,
          NeuralFinishReason.toolUse);
      expect(events.whereType<NeuralUsageEvent>().single.outputTokens, 7);
      expect(
          (body['messages'] as List).first, {'role': 'system', 'content': 'S'});
      expect(((body['tools'] as List).single as Map)['type'], 'function');
    });

    test('invalid JSON arguments are reported, not executed', () async {
      final m = OpenAICompatibleModel(
        model: 'm',
        baseUrl: 'https://x/v1',
        client: sse([
          ev({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'c',
                      'function': {
                        'name': 'get_weather',
                        'arguments': '{"city": Rome'
                      }
                    }
                  ]
                },
                'finish_reason': 'tool_calls'
              }
            ]
          }),
        ]),
      );
      final call =
          (await collect(m, NeuralRequest(messages: [NeuralMessage.user('w')])))
              .whereType<NeuralToolCallEvent>()
              .single
              .call;
      expect(call.argumentsError, isNotNull);
    });
  });

  group('GeminiModel', () {
    test('replays parts with thought signatures and maps function calls',
        () async {
      late Map<String, Object?> body;
      late Uri url;
      final m = GeminiModel(
        apiKey: 'g',
        client: sse([
          ev({
            'candidates': [
              {
                'content': {
                  'role': 'model',
                  'parts': [
                    {'text': 'Let me check', 'thought': true}
                  ]
                }
              }
            ]
          }),
          ev({
            'candidates': [
              {
                'content': {
                  'role': 'model',
                  'parts': [
                    {
                      'functionCall': {
                        'id': 'f1',
                        'name': 'get_weather',
                        'args': {'city': 'Lima'}
                      },
                      'thoughtSignature': 'TS'
                    }
                  ]
                },
                'finishReason': 'STOP'
              }
            ],
            'usageMetadata': {'promptTokenCount': 3, 'candidatesTokenCount': 4}
          }),
        ], onRequest: (r, b) {
          url = r.url;
          body = jsonDecode(b) as Map<String, Object?>;
        }),
      );
      final events = await collect(
          m,
          NeuralRequest(
              messages: [NeuralMessage.user('w')], tools: [_weather]));
      expect(
          url.path, endsWith('/models/gemini-3.8-flash:streamGenerateContent'));
      expect(url.queryParameters['alt'], 'sse');
      final decl = (((body['tools'] as List).single
              as Map)['functionDeclarations'] as List)
          .single as Map;
      expect(decl['parametersJsonSchema'], _weather.parameters);
      expect(body.containsKey('temperature'), isFalse);
      expect(
          events.whereType<NeuralReasoningDelta>().single.text, 'Let me check');
      final fin = events.last as NeuralFinishEvent;
      expect(fin.reason, NeuralFinishReason.toolUse);
      final wire = m.toWire([
        NeuralMessage(
            role: NeuralRole.assistant,
            parts: const [],
            providerContent: fin.providerContent),
        NeuralMessage(role: NeuralRole.tool, parts: const [
          NeuralToolResult(callId: 'f1', name: 'get_weather', result: 'sunny'),
        ]),
      ]);
      expect(((wire[0]['parts'] as List)[1] as Map)['thoughtSignature'], 'TS');
      expect(((wire[1]['parts'] as List).single as Map)['functionResponse'], {
        'id': 'f1',
        'name': 'get_weather',
        'response': {'result': 'sunny'}
      });
    });
  });

  group('GenkitFlowModel', () {
    test('streams message chunks and surfaces flow errors', () async {
      late Map<String, Object?> body;
      final m = GenkitFlowModel(
        url: Uri.parse('https://api.example.com/chatFlow'),
        client: sse([
          'data: {"message": "Hel"}\n\n',
          'data: {"message": {"text": "lo"}}\n\n',
          'data: {"result": "Hello"}\n\n',
        ], onRequest: (r, b) {
          body = jsonDecode(b) as Map<String, Object?>;
          expect(r.headers['accept'], 'text/event-stream');
          expect(r.url.queryParameters['stream'], 'true');
        }),
      );
      final events = await collect(
          m, NeuralRequest(messages: [NeuralMessage.user('hey')]));
      expect(events.whereType<NeuralTextDelta>().map((e) => e.text).join(),
          'Hello');
      expect((body['data']! as Map)['prompt'], 'hey');

      final failing = GenkitFlowModel(
        url: Uri.parse('https://x/f'),
        client: sse([
          'error: {"error": {"status": "INTERNAL", "message": "nope"}}\n\n'
        ]),
      );
      await expectLater(
        collect(failing, NeuralRequest(messages: [NeuralMessage.user('x')])),
        throwsA(
            isA<NeuralModelException>().having((e) => e.message, 'm', 'nope')),
      );
    });
  });

  group('NeuralTool validation', () {
    test('checks required keys, types, enums, nesting', () {
      final t = NeuralTool(
        name: 't',
        description: '',
        parameters: const {
          'type': 'object',
          'properties': {
            'n': {'type': 'integer'},
            'mode': {
              'type': 'string',
              'enum': ['a', 'b']
            },
            'list': {
              'type': 'array',
              'items': {'type': 'number'}
            },
          },
          'required': ['n'],
        },
        handler: (a, c) => null,
      );
      expect(t.validate({'n': 2}), isEmpty);
      expect(t.validate({'n': 2.0}), isEmpty,
          reason: 'integral double is an integer');
      expect(t.validate({}), ['\$.n: required']);
      expect(t.validate({'n': 'x'}), ['\$.n: expected integer']);
      expect(
          t.validate({'n': 1, 'mode': 'c'}).single, contains('must be one of'));
      expect(
          t.validate({
            'n': 1,
            'list': [1, 'x']
          }).single,
          contains('\$.list[1]'));
    });
  });

  group('NeuralAgent', () {
    NeuralAgent agentWith(List<ScriptedTurn> turns,
        {List<NeuralTool> tools = const [], NeuralUiCatalog? ui}) {
      var i = 0;
      return NeuralAgent(
        model: ScriptedModel((r) => turns[i++ % turns.length],
            wordDelay: Duration.zero, thinkDelay: Duration.zero),
        tools: tools,
        uiCatalog: ui,
      );
    }

    test('runs the tool loop and records results in order', () async {
      final agent = agentWith([
        const ScriptedTurn(text: 'Checking.', toolCalls: [
          NeuralToolCall(
              id: 'a', name: 'get_weather', arguments: {'city': 'Oslo'}),
          NeuralToolCall(id: 'b', name: 'get_weather', arguments: {}),
          NeuralToolCall(id: 'c', name: 'nope'),
        ]),
        const ScriptedTurn(text: 'Oslo is 21°C.'),
      ], tools: [
        _weather
      ]);
      final phases = <NeuralAgentPhase>[];
      agent.addListener(() => phases.add(agent.phase));
      await agent.send('Weather?');
      final ms = agent.messages;
      expect(ms.map((m) => m.role), [
        NeuralRole.user,
        NeuralRole.assistant,
        NeuralRole.tool,
        NeuralRole.assistant,
      ]);
      final results = ms[2].parts.cast<NeuralToolResult>();
      expect(results.map((r) => r.callId), ['a', 'b', 'c']);
      expect(results[0].isError, isFalse);
      expect(results[1].result, contains('required'));
      expect(results[2].result, contains('Unknown tool'));
      expect(ms.last.text, 'Oslo is 21°C.');
      expect(agent.phase, NeuralAgentPhase.idle);
      expect(
          phases,
          containsAllInOrder([
            NeuralAgentPhase.thinking,
            NeuralAgentPhase.usingTool,
            NeuralAgentPhase.idle,
          ]));
      agent.dispose();
    });

    test('stops after maxSteps even if the model keeps calling tools',
        () async {
      final agent = NeuralAgent(
        maxSteps: 3,
        tools: [_weather],
        model: ScriptedModel(
          (r) => const ScriptedTurn(toolCalls: [
            NeuralToolCall(
                id: 'x', name: 'get_weather', arguments: {'city': 'A'}),
          ]),
          wordDelay: Duration.zero,
          thinkDelay: Duration.zero,
        ),
      );
      await agent.send('loop');
      expect(agent.messages.where((m) => m.role == NeuralRole.assistant),
          hasLength(3));
      agent.dispose();
    });

    test('approval gate declines sensitive tools', () async {
      var ran = false;
      final pay = NeuralTool(
        name: 'pay',
        description: 'Pays',
        requiresApproval: true,
        handler: (a, c) => ran = true,
      );
      final agent = agentWith([
        const ScriptedTurn(toolCalls: [NeuralToolCall(id: 'p', name: 'pay')]),
        const ScriptedTurn(text: 'Okay, not paying.'),
      ], tools: [
        pay
      ])
        ..onApproveTool = (call) async => false;
      await agent.send('pay');
      expect(ran, isFalse);
      final r = agent.messages[2].parts.single as NeuralToolResult;
      expect(r.isError, isTrue);
      expect(r.resultText, contains('declined'));
      agent.dispose();
    });

    test('retries retryable errors before any output, then succeeds', () async {
      var calls = 0;
      final agent = NeuralAgent(
        maxRetries: 2,
        model: CallbackModel((r) async* {
          calls++;
          if (calls < 3) {
            throw const NeuralModelException('overloaded',
                statusCode: 529, retryAfter: Duration.zero);
          }
          yield const NeuralTextDelta('ok');
        }),
      );
      await agent.send('x');
      expect(calls, 3);
      expect(agent.messages.last.text, 'ok');
      agent.dispose();
    });

    test('non-retryable errors surface; retry() runs again', () async {
      var fail = true;
      final agent = NeuralAgent(
        model: CallbackModel((r) async* {
          if (fail) {
            throw const NeuralModelException('bad key', statusCode: 401);
          }
          yield const NeuralTextDelta('fixed');
        }),
      );
      await agent.send('x');
      expect(agent.phase, NeuralAgentPhase.error);
      expect((agent.error! as NeuralModelException).statusCode, 401);
      fail = false;
      await agent.retry();
      expect(agent.phase, NeuralAgentPhase.idle);
      expect(agent.messages.last.text, 'fixed');
      agent.dispose();
    });

    test('stop() cancels mid-stream and keeps the partial answer', () async {
      final gate = Completer<void>();
      final agent = NeuralAgent(
        model: CallbackModel((r) async* {
          yield const NeuralTextDelta('partial ');
          await gate.future;
          yield const NeuralTextDelta('never');
        }),
      );
      final run = agent.send('x');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(agent.streamingText.value, 'partial ');
      agent.stop();
      gate.complete();
      await run;
      expect(agent.phase, NeuralAgentPhase.idle);
      expect(agent.messages.last.text, 'partial ');
      agent.dispose();
    });

    test('render_ui attaches a UI part; invalid specs report errors', () async {
      final agent = agentWith([
        const ScriptedTurn(toolCalls: [
          NeuralToolCall(id: 'u', name: 'render_ui', arguments: {
            'component': {
              'type': 'gauge',
              'props': {'value': 72, 'label': 'CPU'}
            },
          }),
          NeuralToolCall(id: 'v', name: 'render_ui', arguments: {
            'component': {'type': 'hologram'},
          }),
        ]),
        const ScriptedTurn(text: 'Here you go.'),
      ], ui: NeuralUiCatalog.standard());
      await agent.send('show cpu');
      final assistant = agent.messages[1];
      expect(assistant.parts.whereType<NeuralUiPart>().single.spec['type'],
          'gauge');
      final results = agent.messages[2].parts.cast<NeuralToolResult>();
      expect(results[0].isError, isFalse);
      expect(results[1].isError, isTrue);
      expect(results[1].resultText, contains('must be one of'));
      agent.dispose();
    });

    test('messages round-trip through JSON', () {
      final m = NeuralMessage(
        role: NeuralRole.assistant,
        parts: const [
          NeuralReasoningPart('r'),
          NeuralTextPart('t'),
          NeuralToolCall(id: 'i', name: 'n', arguments: {'a': 1}),
          NeuralUiPart({
            'type': 'text',
            'props': {'text': 'x'}
          }),
        ],
        providerContent: const {
          'anthropic': [
            {'type': 'text', 'text': 't'}
          ]
        },
      );
      final back = NeuralMessage.fromJson(
          jsonDecode(jsonEncode(m.toJson())) as Map<String, Object?>);
      expect(back.id, m.id);
      expect(back.parts.map((p) => p.runtimeType),
          m.parts.map((p) => p.runtimeType));
      expect(back.providerContent, m.providerContent);
    });

    test('voice: listen sends the transcript, replies are spoken', () async {
      final speech = SimulatedSpeech(
          phrases: ['hello there'], wordInterval: Duration.zero);
      final agent = agentWith([const ScriptedTurn(text: 'Hi! How can I help?')])
        ..speechToText = speech.stt
        ..textToSpeech = speech.tts
        ..speakReplies = true;
      final phases = <NeuralAgentPhase>[];
      agent.addListener(() => phases.add(agent.phase));
      await agent.listen();
      expect(agent.messages.first.text, 'hello there');
      expect(agent.messages.last.text, 'Hi! How can I help?');
      expect(
          phases,
          containsAllInOrder([
            NeuralAgentPhase.listening,
            NeuralAgentPhase.thinking,
            NeuralAgentPhase.speaking,
            NeuralAgentPhase.idle,
          ]));
      agent.dispose();
    });

    test('web speech is unavailable off the web', () {
      expect(WebSpeechToText().isAvailable, isFalse);
      expect(WebTextToSpeech().isAvailable, isFalse);
    });
  });

  group('Generative UI', () {
    testWidgets('renders the standard catalog and handles bad specs',
        (tester) async {
      final catalog = NeuralUiCatalog.standard();
      final actions = <String>[];
      await tester.pumpWidget(harness(SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: NeuralUiSurface(
            catalog: catalog,
            onAction: (a, d) => actions.add(a),
            spec: const {
              'type': 'card',
              'props': {'title': 'Today'},
              'children': [
                {
                  'type': 'row',
                  'children': [
                    {
                      'type': 'stat',
                      'props': {
                        'label': 'Steps',
                        'value': '8,240',
                        'delta': '+12%'
                      }
                    },
                    {
                      'type': 'gauge',
                      'props': {'value': '64', 'unit': '%', 'label': 'Goal'}
                    },
                  ]
                },
                {
                  'type': 'sparkline',
                  'props': {
                    'data': [1, '2', 3]
                  }
                },
                {
                  'type': 'progress',
                  'props': {'value': 0.4, 'label': 'Upload'}
                },
                {
                  'type': 'list',
                  'props': {
                    'items': [
                      {'title': 'Run', 'trailing': '5 km'}
                    ]
                  }
                },
                {
                  'type': 'buttons',
                  'props': {
                    'options': [
                      {'label': 'More', 'action': 'show more'}
                    ]
                  }
                },
                {'type': 'hologram'},
                'not a map',
              ],
            },
          ),
        ),
      )));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('Today'), findsOneWidget);
      expect(find.textContaining('8,240', findRichText: true), findsOneWidget);
      expect(find.text('Unsupported component "hologram"'), findsOneWidget);
      expect(find.text('Invalid component'), findsOneWidget);
      await tester.tap(find.text('More'));
      expect(actions, ['show more']);
      expect(tester.takeException(), isNull);
    });

    test('tool description documents every component', () {
      final c = NeuralUiCatalog.standard();
      for (final name in c.components.keys) {
        expect(c.tool.description, contains('- $name'));
      }
      expect(c.jsonSchemas['gauge']!['required'], ['value']);
      expect(c.validate({'type': 'gauge', 'props': {}}).single,
          contains('value: required'));
    });
  });

  group('RehoboamController', () {
    test('tools fly the HUD to a location and back', () async {
      final c = RehoboamController();
      final show = c.tools.firstWhere((t) => t.name == 'show_on_globe');
      await show.handler({
        'latitude': 35.68,
        'longitude': 499.69,
        'label': 'Tokyo',
        'points': [
          {'lat': 1, 'lon': 2, 'mag': 5},
        ]
      }, const NeuralToolContext(callId: 'x'));
      expect(c.mode, HudMode.earth);
      expect(c.longitude, closeTo(139.69, 1e-9),
          reason: 'normalized to -180..180');
      expect(c.bottomLabel, 'Tokyo');
      expect(c.points.single['mag'], 5);
      final pointsBefore = c.points;
      c.level.value = 0.9;
      expect(identical(c.points, pointsBefore), isTrue,
          reason: 'stable identity');
      await c.tools
          .firstWhere((t) => t.name == 'show_hud_ring')
          .handler({}, const NeuralToolContext(callId: 'y'));
      expect(c.mode, HudMode.ring);
      c.dispose();
    });

    test('follows an agent', () async {
      final agent = NeuralAgent(
        model: ScriptedModel((r) => const ScriptedTurn(text: 'ok'),
            wordDelay: Duration.zero, thinkDelay: Duration.zero),
      );
      final c = RehoboamController()..bindAgent(agent);
      final faces = <AiFaceMode>{};
      c.addListener(() => faces.add(c.face));
      await agent.send('hi');
      expect(faces, contains(AiFaceMode.speaking));
      expect(c.topLabel, 'Standing by');
      c.dispose();
      agent.dispose();
    });

    testWidgets('RehoboamHud renders from the controller', (tester) async {
      final c = RehoboamController()..showOnGlobe(10, 20, label: 'Here');
      await tester.pumpWidget(harness(RehoboamHud(controller: c, size: 240)));
      await tester.pump();
      final hud =
          tester.widget<AiThinkingAnimation>(find.byType(AiThinkingAnimation));
      expect(hud.hudMode, HudMode.earth);
      expect(hud.targetLat, 10);
      expect(hud.bottomLabel, 'Here');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('NeuralChatView', () {
    testWidgets('full conversation with tools, UI, reasoning and errors',
        (tester) async {
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var turn = 0;
      final agent = NeuralAgent(
        tools: [_weather],
        uiCatalog: NeuralUiCatalog.standard(),
        model: ScriptedModel(
          (r) => switch (turn++) {
            0 => const ScriptedTurn(
                  reasoning: 'The user wants weather.',
                  text: 'Let me check.',
                  toolCalls: [
                    NeuralToolCall(
                        id: 'w',
                        name: 'get_weather',
                        arguments: {'city': 'Oslo'}),
                    NeuralToolCall(id: 'u', name: 'render_ui', arguments: {
                      'component': {
                        'type': 'stat',
                        'props': {'label': 'Oslo', 'value': '21', 'unit': '°C'}
                      },
                    }),
                  ]),
            _ => const ScriptedTurn(text: 'It is **21°C** and sunny.'),
          },
          wordDelay: const Duration(milliseconds: 10),
          thinkDelay: const Duration(milliseconds: 50),
        ),
      );
      await tester.pumpWidget(harness(
        Scaffold(
            body: NeuralChatView(
                agent: agent,
                title: 'Rehoboam',
                suggestions: const ['Weather in Oslo'])),
      ));
      expect(find.text('Weather in Oslo'), findsOneWidget);
      await tester.tap(find.text('Weather in Oslo'));
      await pumpFor(tester, const Duration(milliseconds: 30));
      expect(find.text('Weather in Oslo'), findsOneWidget,
          reason: 'now the user bubble');
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.textContaining('21°C', findRichText: true), findsWidgets);
      expect(find.textContaining('Used get weather'), findsOneWidget);
      expect(find.text('Thought process'), findsOneWidget);
      expect(find.textContaining('Oslo', findRichText: true), findsWidgets);
      expect(tester.takeException(), isNull);

      // Typing and sending.
      await tester.enterText(find.byType(TextField), 'thanks');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('thanks'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      agent.dispose();
    });

    testWidgets('error notice with retry, RTL and dark', (tester) async {
      var fail = true;
      final agent = NeuralAgent(
        model: CallbackModel((r) async* {
          if (fail) throw const NeuralModelException('nope', statusCode: 401);
          yield const NeuralTextDelta('recovered');
        }),
      );
      await tester.pumpWidget(harness(
          Scaffold(body: NeuralChatView(agent: agent)),
          rtl: true,
          dark: true));
      await agent.send('x');
      await pumpFor(tester, const Duration(milliseconds: 100));
      expect(find.textContaining('Authentication failed'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(
          find.textContaining('recovered', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      agent.dispose();
    });

    testWidgets('mic button appears with speech and drives listening',
        (tester) async {
      final speech = SimulatedSpeech(
          phrases: ['hello'], wordInterval: const Duration(milliseconds: 20));
      final agent = NeuralAgent(
        model: ScriptedModel((r) => const ScriptedTurn(text: 'hey'),
            wordDelay: Duration.zero, thinkDelay: Duration.zero),
        speechToText: speech.stt,
      );
      await tester
          .pumpWidget(harness(Scaffold(body: NeuralChatView(agent: agent))));
      await tester.tap(find.byTooltip('Speak'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(agent.phase, NeuralAgentPhase.listening);
      expect(find.byType(NeuralWaveform), findsOneWidget);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('hello'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      agent.dispose();
    });
  });

  testWidgets('markdown renders headings, bullets, bold and code',
      (tester) async {
    await tester.pumpWidget(harness(const SizedBox(
      width: 360,
      child: NeuralMarkdownText(
          '# Title\n- **bold** item\n1. `code` step\n```\nprint(1);\n```'),
    )));
    expect(find.textContaining('Title', findRichText: true), findsOneWidget);
    expect(
        find.textContaining('bold item', findRichText: true), findsOneWidget);
    expect(
        find.textContaining('code step', findRichText: true), findsOneWidget);
    expect(find.text('print(1);'), findsOneWidget);
  });
}
