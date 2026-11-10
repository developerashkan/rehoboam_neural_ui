import 'package:flutter/material.dart';

import '../widgets/neural_gauge.dart';
import '../widgets/neural_glass_card.dart';
import '../widgets/neural_progress.dart';
import '../widgets/neural_sparkline.dart';
import 'neural_tool.dart';

/// Builds one generated component.
typedef NeuralUiBuilder = Widget Function(
  BuildContext context,
  NeuralUiProps props,
  List<Widget> children,
  NeuralUiContext ui,
);

/// Typed, forgiving access to a component's props (models send numbers as
/// strings, ints as doubles, and so on).
class NeuralUiProps {
  /// Wraps raw props.
  const NeuralUiProps(this.raw);

  /// The raw JSON map.
  final Map<String, Object?> raw;

  /// A string prop.
  String? string(String k) {
    final v = raw[k];
    return v == null ? null : '$v';
  }

  /// A number prop.
  double? number(String k) {
    final v = raw[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// A list of numbers.
  List<double> numbers(String k) {
    final v = raw[k];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is num)
          e.toDouble()
        else if (e is String)
          double.tryParse(e) ?? double.nan,
    ];
  }

  /// A list of maps.
  List<Map<String, Object?>> maps(String k) {
    final v = raw[k];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map) e.map((k, v) => MapEntry('$k', v)),
    ];
  }
}

/// What a component can do back to the app.
class NeuralUiContext {
  /// Creates a context.
  const NeuralUiContext({this.onAction});

  /// Called when generated UI triggers an action (a button tap).
  final void Function(String action, Map<String, Object?> data)? onAction;
}

/// One component the model may use.
@immutable
class NeuralUiComponent {
  /// Creates a component.
  const NeuralUiComponent({
    required this.name,
    required this.description,
    required this.builder,
    this.props = const {'type': 'object', 'properties': {}},
    this.acceptsChildren = false,
  });

  /// Type name the model writes in `"type"`.
  final String name;

  /// When to use it (the model reads this).
  final String description;

  /// JSON Schema of `"props"`.
  final Map<String, Object?> props;

  /// Whether `"children"` are rendered.
  final bool acceptsChildren;

  /// Renders it.
  final NeuralUiBuilder builder;
}

/// The components a model can compose into generated UI, plus the
/// `render_ui` tool that lets it do so.
///
/// Specs are plain JSON: `{"type": "gauge", "props": {...}, "children":
/// [...]}`. [jsonSchemas] exposes every component's prop schema, so the
/// same catalog can be registered with A2UI, Genkit, or any function-
/// calling framework.
class NeuralUiCatalog {
  /// Creates a catalog from [components].
  NeuralUiCatalog(List<NeuralUiComponent> components,
      {this.toolName = 'render_ui'})
      : components = {for (final c in components) c.name: c};

  /// Layout primitives plus the neural widgets: `column`, `row`, `card`,
  /// `text`, `stat`, `gauge`, `sparkline`, `progress`, `list`, `buttons`.
  factory NeuralUiCatalog.standard({
    List<NeuralUiComponent> extra = const [],
    String toolName = 'render_ui',
  }) =>
      NeuralUiCatalog([..._standard, ...extra], toolName: toolName);

  /// Components by name.
  final Map<String, NeuralUiComponent> components;

  /// Name of the rendering tool.
  final String toolName;

  /// Every component's prop schema, by name.
  Map<String, Map<String, Object?>> get jsonSchemas =>
      {for (final c in components.values) c.name: c.props};

  /// The schema of one component spec (recursive via `children`).
  Map<String, Object?> get componentSchema => {
        'type': 'object',
        'properties': {
          'type': {'type': 'string', 'enum': components.keys.toList()},
          'props': {'type': 'object'},
          'children': {
            'type': 'array',
            'items': {'type': 'object'},
          },
        },
        'required': ['type'],
      };

  /// The tool to give the model. Its description documents every
  /// component and its props.
  NeuralTool get tool => NeuralTool(
        name: toolName,
        description: [
          'Show rich UI to the user inline in the chat (cards, KPIs, charts, '
              'progress, lists, quick-reply buttons) instead of long text when '
              'data is visual. Pass one root component; nest with "children".',
          'Components:',
          for (final c in components.values)
            '- ${c.name}${c.acceptsChildren ? ' (children)' : ''}: ${c.description} '
                'props: ${_propsDoc(c.props)}',
        ].join('\n'),
        parameters: {
          'type': 'object',
          'properties': {'component': componentSchema},
          'required': ['component'],
        },
        handler: (args, ctx) {
          final problems = validate(args['component']);
          if (problems.isNotEmpty) {
            throw ArgumentError('Invalid component: ${problems.join('; ')}');
          }
          return {'rendered': true};
        },
      );

  /// Validates a spec tree; returns problems (empty when renderable).
  List<String> validate(Object? spec, {String path = r'$', int depth = 0}) {
    if (depth > 8) return ['$path: nested too deeply'];
    if (spec is! Map) return ['$path: component must be an object'];
    final type = spec['type'];
    final c = components[type];
    if (c == null) return ['$path: unknown component "$type"'];
    final errors = <String>[];
    final props = spec['props'] ?? const <String, Object?>{};
    errors.addAll(validateJson(props, c.props, path: '$path.props'));
    final children = spec['children'];
    if (children is List) {
      if (children.length > 50) errors.add('$path.children: too many');
      for (var i = 0; i < children.length && i < 50; i++) {
        errors.addAll(validate(children[i],
            path: '$path.children[$i]', depth: depth + 1));
      }
    }
    return errors;
  }

  static String _propsDoc(Map<String, Object?> schema) {
    final p = schema['properties'];
    if (p is! Map || p.isEmpty) return '{}';
    final req = (schema['required'] as List?)?.toSet() ?? const {};
    return '{${p.entries.map((e) {
      final s = e.value is Map ? e.value as Map : const {};
      final t = s['enum'] != null ? (s['enum'] as List).join('|') : s['type'];
      return '${e.key}${req.contains(e.key) ? '' : '?'}: $t';
    }).join(', ')}}';
  }
}

/// Renders a generated component spec with a [NeuralUiCatalog].
/// Unknown types and bad props render a small notice, never an exception.
class NeuralUiSurface extends StatelessWidget {
  /// Creates a surface.
  const NeuralUiSurface({
    super.key,
    required this.spec,
    required this.catalog,
    this.onAction,
  });

  /// The component tree.
  final Map<String, Object?> spec;

  /// Available components.
  final NeuralUiCatalog catalog;

  /// Button / action callback.
  final void Function(String action, Map<String, Object?> data)? onAction;

  @override
  Widget build(BuildContext context) =>
      _build(context, spec, 0, NeuralUiContext(onAction: onAction));

  Widget _build(
      BuildContext context, Object? spec, int depth, NeuralUiContext ui) {
    if (spec is! Map || depth > 8) return const _UiNotice('Invalid component');
    final c = catalog.components['${spec['type']}'];
    if (c == null) return _UiNotice('Unsupported component "${spec['type']}"');
    final props = spec['props'] is Map
        ? (spec['props'] as Map).map((k, v) => MapEntry('$k', v))
        : <String, Object?>{};
    final rawChildren = spec['children'];
    final children = c.acceptsChildren && rawChildren is List
        ? [
            for (final child in rawChildren.take(50))
              _build(context, child, depth + 1, ui),
          ]
        : const <Widget>[];
    try {
      return c.builder(context, NeuralUiProps(props), children, ui);
    } on Object {
      return _UiNotice('Could not render "${c.name}"');
    }
  }
}

class _UiNotice extends StatelessWidget {
  const _UiNotice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
    );
  }
}

Map<String, Object?> _obj(Map<String, Object?> props,
        [List<String> required = const []]) =>
    {
      'type': 'object',
      'properties': props,
      if (required.isNotEmpty) 'required': required
    };

const _str = {'type': 'string'};
const _num = {'type': 'number'};

Widget _gap(List<Widget> children, double gap, Axis axis) {
  final out = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) {
      out.add(
          axis == Axis.vertical ? SizedBox(height: gap) : SizedBox(width: gap));
    }
    out.add(
        axis == Axis.horizontal ? Expanded(child: children[i]) : children[i]);
  }
  return axis == Axis.vertical
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out)
      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: out);
}

final List<NeuralUiComponent> _standard = [
  NeuralUiComponent(
    name: 'column',
    description: 'Stacks children vertically.',
    props: _obj({'gap': _num}),
    acceptsChildren: true,
    builder: (c, p, children, ui) =>
        _gap(children, p.number('gap') ?? 12, Axis.vertical),
  ),
  NeuralUiComponent(
    name: 'row',
    description: 'Places children side by side with equal width (max 4).',
    props: _obj({'gap': _num}),
    acceptsChildren: true,
    builder: (c, p, children, ui) =>
        _gap(children.take(4).toList(), p.number('gap') ?? 12, Axis.horizontal),
  ),
  NeuralUiComponent(
    name: 'card',
    description: 'A glass card with an optional title and subtitle.',
    props: _obj({'title': _str, 'subtitle': _str}),
    acceptsChildren: true,
    builder: (c, p, children, ui) {
      final t = Theme.of(c).textTheme;
      return NeuralGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (p.string('title') != null)
              Text(p.string('title')!,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (p.string('subtitle') != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(p.string('subtitle')!,
                    style: t.bodySmall?.copyWith(
                        color: Theme.of(c).colorScheme.onSurfaceVariant)),
              ),
            if (children.isNotEmpty) const SizedBox(height: 12),
            ..._withGaps(children),
          ],
        ),
      );
    },
  ),
  NeuralUiComponent(
    name: 'text',
    description: 'A paragraph or heading.',
    props: _obj({
      'text': _str,
      'style': {
        'type': 'string',
        'enum': ['title', 'body', 'caption'],
      },
    }, [
      'text'
    ]),
    builder: (c, p, children, ui) {
      final t = Theme.of(c).textTheme;
      final style = switch (p.string('style')) {
        'title' => t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        'caption' => t.bodySmall
            ?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant),
        _ => t.bodyMedium,
      };
      return Text(p.string('text') ?? '', style: style);
    },
  ),
  NeuralUiComponent(
    name: 'stat',
    description: 'One headline number with label, unit and change.',
    props: _obj({'label': _str, 'value': _str, 'unit': _str, 'delta': _str},
        ['label', 'value']),
    builder: (c, p, children, ui) {
      final t = Theme.of(c).textTheme;
      final scheme = Theme.of(c).colorScheme;
      final delta = p.string('delta');
      final negative = delta != null && delta.trim().startsWith('-');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p.string('label')!.toUpperCase(),
              style: t.labelSmall?.copyWith(
                  letterSpacing: 1.2, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: p.string('value'),
                  style:
                      t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              if (p.string('unit') != null)
                TextSpan(
                    text: ' ${p.string('unit')}',
                    style:
                        t.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ])),
          ),
          if (delta != null)
            Text(delta,
                style: t.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: negative ? scheme.error : scheme.primary)),
        ],
      );
    },
  ),
  NeuralUiComponent(
    name: 'gauge',
    description:
        'A KPI ring for a value within a range (percentages, scores, load).',
    props: _obj(
        {'label': _str, 'value': _num, 'min': _num, 'max': _num, 'unit': _str},
        ['value']),
    builder: (c, p, children, ui) => Center(
      child: LayoutBuilder(
        builder: (c, box) => NeuralGauge(
          size:
              (box.maxWidth.isFinite ? box.maxWidth : 180.0).clamp(80.0, 200.0),
          value: p.number('value') ?? 0,
          min: p.number('min') ?? 0,
          max: p.number('max') ?? 100,
          unit: p.string('unit'),
          label: p.string('label'),
        ),
      ),
    ),
  ),
  NeuralUiComponent(
    name: 'sparkline',
    description: 'A trend line over time (oldest first).',
    props: _obj({
      'label': _str,
      'data': {'type': 'array', 'items': _num},
    }, [
      'data'
    ]),
    builder: (c, p, children, ui) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.string('label') != null)
          Text(p.string('label')!, style: Theme.of(c).textTheme.labelLarge),
        NeuralSparkline(
            data: p.numbers('data'),
            height: 96,
            semanticsLabel: p.string('label')),
      ],
    ),
  ),
  NeuralUiComponent(
    name: 'progress',
    description: 'A labelled progress bar, value 0..1.',
    props: _obj({'label': _str, 'value': _num}, ['value']),
    builder: (c, p, children, ui) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.string('label') != null)
          Text(p.string('label')!, style: Theme.of(c).textTheme.labelLarge),
        NeuralProgress.linear(
            value: p.number('value') ?? 0, semanticsLabel: p.string('label')),
      ],
    ),
  ),
  NeuralUiComponent(
    name: 'list',
    description:
        'A list of items with title and optional subtitle and trailing text.',
    props: _obj({
      'items': {
        'type': 'array',
        'items': _obj(
            {'title': _str, 'subtitle': _str, 'trailing': _str}, ['title']),
      },
    }, [
      'items'
    ]),
    builder: (c, p, children, ui) {
      final t = Theme.of(c).textTheme;
      final scheme = Theme.of(c).colorScheme;
      final items = p.maps('items').take(30).toList();
      return Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.4)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${items[i]['title']}', style: t.bodyLarge),
                        if (items[i]['subtitle'] != null)
                          Text('${items[i]['subtitle']}',
                              style: t.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (items[i]['trailing'] != null)
                    Text('${items[i]['trailing']}',
                        style: t.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ],
      );
    },
  ),
  NeuralUiComponent(
    name: 'buttons',
    description:
        'Quick-reply buttons; tapping one sends its action text to you as the user.',
    props: _obj({
      'options': {
        'type': 'array',
        'items': _obj({'label': _str, 'action': _str}, ['label']),
      },
    }, [
      'options'
    ]),
    builder: (c, p, children, ui) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in p.maps('options').take(8))
          ActionChip(
            label: Text('${o['label']}'),
            onPressed: ui.onAction == null
                ? null
                : () => ui.onAction!('${o['action'] ?? o['label']}', const {}),
          ),
      ],
    ),
  ),
];

List<Widget> _withGaps(List<Widget> children) => [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        children[i],
      ],
    ];
