import 'dart:async';

import 'package:flutter/foundation.dart';

/// Context passed to a running tool.
class NeuralToolContext {
  /// Creates a context.
  const NeuralToolContext({required this.callId});

  /// The provider's call id.
  final String callId;
}

/// A function the model can call.
///
/// [parameters] is a JSON Schema object (`type: object`). The same tool
/// works with every provider: it is translated to Claude `input_schema`,
/// OpenAI `function.parameters` and Gemini `parametersJsonSchema`.
///
/// ```dart
/// final weather = NeuralTool(
///   name: 'get_weather',
///   description: 'Current weather for a city.',
///   parameters: {
///     'type': 'object',
///     'properties': {'city': {'type': 'string'}},
///     'required': ['city'],
///   },
///   handler: (args, ctx) async => {'tempC': 21, 'city': args['city']},
/// );
/// ```
@immutable
class NeuralTool {
  /// Creates a tool.
  const NeuralTool({
    required this.name,
    required this.description,
    required this.handler,
    this.parameters = const {'type': 'object', 'properties': {}},
    this.requiresApproval = false,
  });

  /// Unique name (`[a-zA-Z0-9_-]{1,64}`).
  final String name;

  /// What it does and when to use it; the model reads this.
  final String description;

  /// JSON Schema of the arguments.
  final Map<String, Object?> parameters;

  /// Runs the tool. Return any JSON-encodable value; throw to report an
  /// error to the model.
  final FutureOr<Object?> Function(
      Map<String, Object?> arguments, NeuralToolContext context) handler;

  /// Ask `NeuralAgent.onApproveTool` before running (payments, sending,
  /// deleting...).
  final bool requiresApproval;

  /// Validates [args] against [parameters]; returns a list of problems
  /// (empty when valid). Checks required keys, primitive types, enums and
  /// nested objects / arrays. Unknown keywords are ignored.
  List<String> validate(Map<String, Object?> args) =>
      validateJson(args, parameters, path: r'$');
}

/// Minimal JSON Schema validation used for tool arguments.
List<String> validateJson(Object? value, Map<String, Object?> schema,
    {String path = r'$'}) {
  final errors = <String>[];
  final type = schema['type'];
  bool typeOk(String t) => switch (t) {
        'object' => value is Map,
        'array' => value is List,
        'string' => value is String,
        'integer' =>
          value is int || (value is double && value == value.roundToDouble()),
        'number' => value is num,
        'boolean' => value is bool,
        'null' => value == null,
        _ => true,
      };
  if (type is String && !typeOk(type)) {
    errors.add('$path: expected $type');
    return errors;
  }
  if (type is List && !type.whereType<String>().any(typeOk)) {
    errors.add('$path: expected one of $type');
    return errors;
  }
  final enumValues = schema['enum'];
  if (enumValues is List && !enumValues.contains(value)) {
    errors.add('$path: must be one of $enumValues');
  }
  if (value is Map) {
    final props = schema['properties'];
    final required = schema['required'];
    if (required is List) {
      for (final k in required) {
        if (!value.containsKey(k)) errors.add('$path.$k: required');
      }
    }
    if (props is Map) {
      for (final e in props.entries) {
        if (value.containsKey(e.key) && e.value is Map) {
          errors.addAll(validateJson(
              value[e.key], (e.value as Map).cast<String, Object?>(),
              path: '$path.${e.key}'));
        }
      }
    }
  }
  if (value is List && schema['items'] is Map) {
    final items = (schema['items'] as Map).cast<String, Object?>();
    for (var i = 0; i < value.length; i++) {
      errors.addAll(validateJson(value[i], items, path: '$path[$i]'));
    }
  }
  return errors;
}
