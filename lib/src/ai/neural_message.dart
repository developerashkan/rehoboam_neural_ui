import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Who wrote a [NeuralMessage].
enum NeuralRole {
  /// The person using the app.
  user,

  /// The model.
  assistant,

  /// Tool results fed back to the model.
  tool,
}

/// One piece of a message. Messages are lists of parts so text, images,
/// tool calls, tool results, generated UI and reasoning can interleave.
@immutable
sealed class NeuralPart {
  const NeuralPart();

  /// A JSON form for persistence.
  Map<String, Object?> toJson();

  /// Restores a part written by [toJson].
  static NeuralPart fromJson(Map<String, Object?> j) {
    switch (j['type']) {
      case 'text':
        return NeuralTextPart(j['text'] as String? ?? '');
      case 'image':
        return NeuralImagePart(
          base64Decode(j['data'] as String? ?? ''),
          mimeType: j['mimeType'] as String? ?? 'image/png',
        );
      case 'tool_call':
        return NeuralToolCall(
          id: j['id'] as String? ?? '',
          name: j['name'] as String? ?? '',
          arguments: _map(j['arguments']),
        );
      case 'tool_result':
        return NeuralToolResult(
          callId: j['callId'] as String? ?? '',
          name: j['name'] as String? ?? '',
          result: j['result'],
          isError: j['isError'] == true,
        );
      case 'ui':
        return NeuralUiPart(_map(j['spec']));
      case 'reasoning':
        return NeuralReasoningPart(j['text'] as String? ?? '');
      default:
        return NeuralTextPart(jsonEncode(j));
    }
  }
}

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.map((k, v) => MapEntry('$k', v)) : <String, Object?>{};

/// Plain text.
class NeuralTextPart extends NeuralPart {
  /// Creates a text part.
  const NeuralTextPart(this.text);

  /// The text.
  final String text;

  @override
  Map<String, Object?> toJson() => {'type': 'text', 'text': text};
}

/// An image the user attached.
class NeuralImagePart extends NeuralPart {
  /// Creates an image part from encoded bytes.
  const NeuralImagePart(this.bytes, {this.mimeType = 'image/png'});

  /// Encoded image bytes (PNG, JPEG, WebP...).
  final Uint8List bytes;

  /// MIME type of [bytes].
  final String mimeType;

  /// Base64 of [bytes].
  String get base64 => base64Encode(bytes);

  @override
  Map<String, Object?> toJson() =>
      {'type': 'image', 'mimeType': mimeType, 'data': base64};
}

/// The model asking the app to run a tool.
class NeuralToolCall extends NeuralPart {
  /// Creates a tool call.
  const NeuralToolCall({
    required this.id,
    required this.name,
    this.arguments = const {},
    this.argumentsError,
  });

  /// Set when the provider sent arguments that are not valid JSON (for
  /// example cut off by the output limit). The agent never runs such a
  /// call; it reports the error back to the model instead.
  final String? argumentsError;

  /// Provider id used to match the result.
  final String id;

  /// Tool name.
  final String name;

  /// Parsed arguments.
  final Map<String, Object?> arguments;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'tool_call', 'id': id, 'name': name, 'arguments': arguments};
}

/// The outcome of a [NeuralToolCall].
class NeuralToolResult extends NeuralPart {
  /// Creates a tool result.
  const NeuralToolResult({
    required this.callId,
    required this.name,
    required this.result,
    this.isError = false,
  });

  /// The [NeuralToolCall.id] this answers.
  final String callId;

  /// Tool name.
  final String name;

  /// JSON-encodable result.
  final Object? result;

  /// Whether the tool failed.
  final bool isError;

  /// [result] as text for providers that take strings.
  String get resultText =>
      result is String ? result! as String : jsonEncode(result);

  @override
  Map<String, Object?> toJson() => {
        'type': 'tool_result',
        'callId': callId,
        'name': name,
        'result': result,
        'isError': isError,
      };
}

/// A piece of generated UI (rendered by `NeuralUiSurface`).
class NeuralUiPart extends NeuralPart {
  /// Creates a UI part from a component spec.
  const NeuralUiPart(this.spec);

  /// `{"type": "...", "props": {...}, "children": [...]}`.
  final Map<String, Object?> spec;

  @override
  Map<String, Object?> toJson() => {'type': 'ui', 'spec': spec};
}

/// Model reasoning shown to the user (a summary, never raw thoughts).
class NeuralReasoningPart extends NeuralPart {
  /// Creates a reasoning part.
  const NeuralReasoningPart(this.text);

  /// The summary text.
  final String text;

  @override
  Map<String, Object?> toJson() => {'type': 'reasoning', 'text': text};
}

/// One turn of a conversation.
@immutable
class NeuralMessage {
  /// Creates a message.
  NeuralMessage({
    required this.role,
    required this.parts,
    String? id,
    DateTime? createdAt,
    this.providerContent,
  })  : id = id ?? _nextId(),
        createdAt = createdAt ?? DateTime.now();

  /// A user message with [text] (and optional images).
  factory NeuralMessage.user(String text,
          {List<NeuralImagePart> images = const []}) =>
      NeuralMessage(
        role: NeuralRole.user,
        parts: [...images, if (text.isNotEmpty) NeuralTextPart(text)],
      );

  /// Author.
  final NeuralRole role;

  /// Content.
  final List<NeuralPart> parts;

  /// Stable id.
  final String id;

  /// Creation time.
  final DateTime createdAt;

  /// The provider's own wire form of an assistant turn (for example Claude
  /// content blocks with thinking signatures, or Gemini parts with thought
  /// signatures), keyed by provider id. Providers replay it verbatim so
  /// multi-step tool use stays valid. Opaque to the app.
  final Map<String, Object?>? providerContent;

  static int _counter = 0;
  static String _nextId() =>
      'm${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_counter++).toRadixString(36)}';

  /// All text parts joined.
  String get text =>
      parts.whereType<NeuralTextPart>().map((p) => p.text).join();

  /// Tool calls in this message.
  Iterable<NeuralToolCall> get toolCalls => parts.whereType<NeuralToolCall>();

  /// A copy with replaced fields.
  NeuralMessage copyWith(
          {List<NeuralPart>? parts, Map<String, Object?>? providerContent}) =>
      NeuralMessage(
        role: role,
        parts: parts ?? this.parts,
        id: id,
        createdAt: createdAt,
        providerContent: providerContent ?? this.providerContent,
      );

  /// JSON form for persistence (provider content included).
  Map<String, Object?> toJson() => {
        'id': id,
        'role': role.name,
        'createdAt': createdAt.toIso8601String(),
        'parts': [for (final p in parts) p.toJson()],
        if (providerContent != null) 'providerContent': providerContent,
      };

  /// Restores a message written by [toJson].
  factory NeuralMessage.fromJson(Map<String, Object?> j) => NeuralMessage(
        id: j['id'] as String?,
        role: NeuralRole.values.firstWhere(
          (r) => r.name == j['role'],
          orElse: () => NeuralRole.user,
        ),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
        parts: [
          for (final p in (j['parts'] as List? ?? const []))
            if (p is Map) NeuralPart.fromJson(_map(p)),
        ],
        providerContent:
            j['providerContent'] is Map ? _map(j['providerContent']) : null,
      );
}
