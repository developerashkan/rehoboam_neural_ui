import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';

/// The model the example talks to.
enum DemoProvider {
  /// Offline scripted model (no key needed).
  demo('Offline demo'),

  /// Anthropic Claude.
  claude('Claude'),

  /// Google Gemini.
  gemini('Gemini'),

  /// OpenAI or any compatible endpoint.
  openai('OpenAI-compatible'),

  /// Local Ollama.
  ollama('Ollama (local)');

  const DemoProvider(this.label);

  /// Display name.
  final String label;
}

/// Connection settings typed into the example's settings sheet. Kept in
/// memory only.
class DemoSettings {
  /// Creates settings.
  DemoSettings({
    this.provider = DemoProvider.demo,
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
  });

  /// Provider.
  DemoProvider provider;

  /// API key.
  String apiKey;

  /// Model id override.
  String model;

  /// Base URL override.
  String baseUrl;
}

/// Shared app state: one agent drives the chat, the HUD and the orb.
class AssistantHub {
  /// Creates the hub.
  AssistantHub() {
    hud.bindAgent(agent);
    for (final t in hud.tools) {
      agent.addTool(t);
    }
  }

  /// The HUD controller (also exposed to the model as tools).
  final RehoboamController hud =
      RehoboamController(bottomLabel: 'Ask me anything');

  /// Voice engines: the browser's own on the web, simulated elsewhere.
  late final SimulatedSpeech _sim = SimulatedSpeech(phrases: const [
    'Show me Tokyo on the globe',
    'What is the weather in Lisbon?',
    'Give me a dashboard of the servers',
  ]);

  /// The settings in use.
  final DemoSettings settings = DemoSettings();

  /// The conversation.
  late final NeuralAgent agent = NeuralAgent(
    model: _demoModel(),
    system: 'You are Rehoboam, a concise assistant inside a Flutter app. '
        'Use show_on_globe whenever a place is mentioned. Prefer render_ui '
        'for numbers, comparisons and dashboards. Keep answers short.',
    tools: [weatherTool, serverStatsTool],
    uiCatalog: NeuralUiCatalog.standard(),
    speechToText: _stt(),
    textToSpeech: _tts(),
  );

  NeuralSpeechToText _stt() {
    final web = WebSpeechToText();
    return kIsWeb && web.isAvailable ? web : _sim.stt;
  }

  NeuralTextToSpeech _tts() {
    final web = WebTextToSpeech();
    return kIsWeb && web.isAvailable ? web : _sim.tts;
  }

  /// Applies [settings] (switches the model).
  void apply() {
    final s = settings;
    String or(String v, String d) => v.trim().isEmpty ? d : v.trim();
    agent.model = switch (s.provider) {
      DemoProvider.demo => _demoModel(),
      DemoProvider.claude => ClaudeModel(
          apiKey: s.apiKey.isEmpty ? null : s.apiKey,
          model: or(s.model, 'claude-opus-5-5'),
          baseUrl: or(s.baseUrl, 'https://api.anthropic.com'),
          browserAccess: kIsWeb,
        ),
      DemoProvider.gemini => GeminiModel(
          apiKey: s.apiKey.isEmpty ? null : s.apiKey,
          model: or(s.model, 'gemini-3.8-flash'),
        ),
      DemoProvider.openai => OpenAICompatibleModel(
          apiKey: s.apiKey.isEmpty ? null : s.apiKey,
          model: s.model.trim(),
          baseUrl: or(s.baseUrl, 'https://api.openai.com/v1'),
        ),
      DemoProvider.ollama => OpenAICompatibleModel.ollama(
          model: s.model.trim(),
          baseUrl: or(s.baseUrl, 'http://localhost:11434/v1'),
        ),
    };
  }

  /// Releases resources.
  void dispose() {
    hud.dispose();
    agent.dispose();
  }
}

/// Fake weather data for the demo tool.
final NeuralTool weatherTool = NeuralTool(
  name: 'get_weather',
  description: 'Current weather and the next 8 hours for a city.',
  parameters: const {
    'type': 'object',
    'properties': {
      'city': {'type': 'string', 'description': 'City name'},
    },
    'required': ['city'],
  },
  handler: (args, ctx) {
    final city = '${args['city']}';
    final seed =
        city.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff);
    final r = math.Random(seed);
    final now = 12 + r.nextInt(16);
    return {
      'city': city,
      'tempC': now,
      'condition': [
        'Sunny',
        'Clear',
        'Partly cloudy',
        'Light rain'
      ][r.nextInt(4)],
      'hourly': [
        for (var i = 0; i < 8; i++) now + (math.sin(i / 2) * 3).round()
      ],
      'humidity': 40 + r.nextInt(40),
    };
  },
);

/// Fake infrastructure metrics for the demo tool.
final NeuralTool serverStatsTool = NeuralTool(
  name: 'server_stats',
  description: 'CPU, memory and request rate for the production cluster.',
  handler: (args, ctx) => {
    'cpu': 67,
    'memoryGb': 41,
    'memoryMaxGb': 64,
    'requestsPerMin': [820, 860, 910, 870, 990, 1040, 1010, 1120, 1180, 1150],
    'regions': {
      'eu-west': 'healthy',
      'us-east': 'healthy',
      'ap-south': 'degraded'
    },
  },
);

/// Known places for the offline demo.
const _places = {
  'tokyo': (35.68, 139.69, 'Tokyo, JP'),
  'lisbon': (38.72, -9.14, 'Lisbon, PT'),
  'paris': (48.86, 2.35, 'Paris, FR'),
  'new york': (40.71, -74.0, 'New York, US'),
  'everest': (27.99, 86.93, 'Mount Everest'),
  'sydney': (-33.87, 151.21, 'Sydney, AU'),
  'cairo': (30.04, 31.24, 'Cairo, EG'),
  'tehran': (35.69, 51.39, 'Tehran, IR'),
};

/// An offline model that behaves like a real tool-using assistant, so the
/// example works without a key (and renders deterministic screenshots).
ScriptedModel _demoModel() => ScriptedModel((req) {
      final last = req.messages.last;
      final user =
          req.messages.lastWhere((m) => m.role == NeuralRole.user).text;
      final q = user.toLowerCase();
      final place = _places.entries.where((e) => q.contains(e.key)).firstOrNull;

      // After tools ran: answer from their results.
      if (last.role == NeuralRole.tool) {
        final results = last.parts.whereType<NeuralToolResult>().toList();
        final weather =
            results.where((r) => r.name == 'get_weather').firstOrNull;
        final stats =
            results.where((r) => r.name == 'server_stats').firstOrNull;
        if (weather != null && weather.result is Map) {
          final w = weather.result! as Map;
          return ScriptedTurn(
            text:
                '${w['city']} is **${w['tempC']}°C** and ${'${w['condition']}'.toLowerCase()} '
                'right now, humidity ${w['humidity']}%. The next hours stay mild.',
            toolCalls: [
              NeuralToolCall(id: 'ui_w', name: 'render_ui', arguments: {
                'component': {
                  'type': 'card',
                  'props': {
                    'title': '${w['city']}',
                    'subtitle': '${w['condition']}'
                  },
                  'children': [
                    {
                      'type': 'row',
                      'children': [
                        {
                          'type': 'stat',
                          'props': {
                            'label': 'Now',
                            'value': '${w['tempC']}',
                            'unit': '°C'
                          }
                        },
                        {
                          'type': 'stat',
                          'props': {
                            'label': 'Humidity',
                            'value': '${w['humidity']}',
                            'unit': '%'
                          }
                        },
                      ],
                    },
                    {
                      'type': 'sparkline',
                      'props': {'label': 'Next 8 hours', 'data': w['hourly']}
                    },
                  ],
                },
              }),
            ],
          );
        }
        if (stats != null && stats.result is Map) {
          final s = stats.result! as Map;
          return ScriptedTurn(
            text:
                'The cluster is busy but healthy. **ap-south** is degraded; I would look there first.',
            toolCalls: [
              NeuralToolCall(id: 'ui_s', name: 'render_ui', arguments: {
                'component': {
                  'type': 'card',
                  'props': {
                    'title': 'Production cluster',
                    'subtitle': 'Live, last 10 minutes'
                  },
                  'children': [
                    {
                      'type': 'row',
                      'children': [
                        {
                          'type': 'gauge',
                          'props': {
                            'label': 'CPU',
                            'value': s['cpu'],
                            'unit': '%'
                          }
                        },
                        {
                          'type': 'gauge',
                          'props': {
                            'label': 'Memory',
                            'value': s['memoryGb'],
                            'max': s['memoryMaxGb'],
                            'unit': 'GB'
                          }
                        },
                      ],
                    },
                    {
                      'type': 'sparkline',
                      'props': {
                        'label': 'Requests / min',
                        'data': s['requestsPerMin']
                      }
                    },
                    {
                      'type': 'list',
                      'props': {
                        'items': [
                          for (final e in (s['regions'] as Map).entries)
                            {'title': e.key, 'trailing': e.value},
                        ],
                      },
                    },
                    {
                      'type': 'buttons',
                      'props': {
                        'options': [
                          {
                            'label': 'Open ap-south',
                            'action': 'Show me ap-south details'
                          },
                          {
                            'label': 'Show on globe',
                            'action': 'Show me Tokyo on the globe'
                          },
                        ],
                      },
                    },
                  ],
                },
              }),
            ],
          );
        }
        final shown =
            results.where((r) => r.name == 'show_on_globe').isNotEmpty;
        if (shown && place != null) {
          return ScriptedTurn(
            text:
                'Here is **${place.value.$3}** on the globe. I marked a few recent '
                'seismic events nearby too.',
          );
        }
        // Only UI was rendered: nothing more to say.
        return const ScriptedTurn();
      }

      if (q.contains('weather')) {
        final city = place?.value.$3.split(',').first ?? 'Lisbon';
        return ScriptedTurn(
          reasoning: 'The user wants current conditions for $city. '
              'I will fetch the weather, then show a compact card.',
          text: '',
          toolCalls: [
            NeuralToolCall(
                id: 'w1', name: 'get_weather', arguments: {'city': city}),
          ],
        );
      }
      if (place != null) {
        final (lat, lon, label) = place.value;
        return ScriptedTurn(
          reasoning:
              'A place was mentioned, so I will fly the HUD globe there.',
          toolCalls: [
            NeuralToolCall(id: 'g1', name: 'show_on_globe', arguments: {
              'latitude': lat,
              'longitude': lon,
              'label': label,
              'points': [
                {'lat': lat + 1.2, 'lon': lon - 0.8, 'mag': 4.6},
                {'lat': lat - 2.1, 'lon': lon + 1.9, 'mag': 5.3},
              ],
            }),
          ],
        );
      }
      if (q.contains('server') ||
          q.contains('dashboard') ||
          q.contains('cpu')) {
        return const ScriptedTurn(
          reasoning: 'Fetch live metrics, then summarize them visually.',
          toolCalls: [NeuralToolCall(id: 's1', name: 'server_stats')],
        );
      }
      return const ScriptedTurn(
        text:
            'I can talk to **Claude, Gemini, OpenAI-compatible APIs, Genkit flows** '
            'or a local model, call your tools, and draw live UI right here.\n\n'
            '- Ask for the *weather* somewhere\n'
            '- Ask me to *show a city* on the globe\n'
            '- Ask for a *server dashboard*',
      );
    });

/// Settings sheet to connect a real provider.
Future<void> showDemoSettings(BuildContext context, AssistantHub hub) {
  final s = hub.settings;
  final key = TextEditingController(text: s.apiKey);
  final model = TextEditingController(text: s.model);
  final url = TextEditingController(text: s.baseUrl);
  var provider = s.provider;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Model', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in DemoProvider.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: p == provider,
                    onSelected: (_) => setState(() => provider = p),
                  ),
              ],
            ),
            if (provider != DemoProvider.demo) ...[
              const SizedBox(height: 16),
              if (provider != DemoProvider.ollama)
                TextField(
                  controller: key,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'API key (kept in memory only)'),
                ),
              TextField(
                controller: model,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: provider == DemoProvider.openai ||
                          provider == DemoProvider.ollama
                      ? 'Model id (required)'
                      : 'Model id (optional)',
                ),
              ),
              TextField(
                controller: url,
                decoration: const InputDecoration(
                    labelText: 'Base URL or proxy (optional)'),
              ),
              const SizedBox(height: 8),
              Text(
                'For production, call models through your own backend or a Genkit '
                'flow instead of shipping a key in the app.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              // A model id is needed where there is no sensible default.
              onPressed: (provider == DemoProvider.openai ||
                          provider == DemoProvider.ollama) &&
                      model.text.trim().isEmpty
                  ? null
                  : () {
                      s
                        ..provider = provider
                        ..apiKey = key.text
                        ..model = model.text
                        ..baseUrl = url.text;
                      hub.apply();
                      Navigator.pop(context);
                    },
              child: const Text('Use this model'),
            ),
          ],
        ),
      ),
    ),
  );
}
