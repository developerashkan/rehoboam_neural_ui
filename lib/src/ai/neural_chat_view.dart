import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/neural_clock.dart';
import '../core/neural_theme.dart';
import '../liquid/liquid_widgets.dart';
import '../widgets/neural_orb.dart';
import 'gen_ui.dart';
import 'neural_agent.dart';
import 'neural_message.dart';
import 'neural_model.dart';

/// Localizable strings for [NeuralChatView].
@immutable
class NeuralChatStrings {
  /// Creates strings (English defaults).
  const NeuralChatStrings({
    this.hint = 'Ask anything',
    this.thinking = 'Thinking',
    this.listening = 'Listening…',
    this.retry = 'Retry',
    this.stop = 'Stop',
    this.send = 'Send',
    this.speak = 'Speak',
    this.refusal = 'The model declined to answer this request.',
    this.truncated = 'The answer was cut off at the length limit.',
    this.ranTool = 'Used',
    this.toolFailed = 'Failed',
    this.thought = 'Thought process',
  });

  /// Composer placeholder.
  final String hint;

  /// Shown while waiting for the first token.
  final String thinking;

  /// Shown while listening.
  final String listening;

  /// Retry button.
  final String retry;

  /// Stop button tooltip.
  final String stop;

  /// Send button tooltip.
  final String send;

  /// Mic button tooltip.
  final String speak;

  /// Refusal notice.
  final String refusal;

  /// Truncation notice.
  final String truncated;

  /// Tool chip prefix.
  final String ranTool;

  /// Failed tool chip prefix.
  final String toolFailed;

  /// Reasoning expander title.
  final String thought;
}

/// A complete, modern AI conversation screen for a [NeuralAgent]:
/// a liquid orb that mirrors the agent, streaming answers with reasoning,
/// tool activity, generated UI inline, suggestions, errors with retry, and
/// a glass composer with voice input.
///
/// It is a plain widget: put it in a `Scaffold`, a sheet or a side panel.
class NeuralChatView extends StatefulWidget {
  /// Creates a chat view.
  const NeuralChatView({
    super.key,
    required this.agent,
    this.title,
    this.subtitle,
    this.suggestions = const [],
    this.strings = const NeuralChatStrings(),
    this.showHeader = true,
    this.emptyState,
    this.maxContentWidth = 760,
    this.onSubmitted,
  });

  /// The conversation.
  final NeuralAgent agent;

  /// Header title (e.g. the assistant's name).
  final String? title;

  /// Header subtitle (defaults to the agent's phase).
  final String? subtitle;

  /// Starter prompts shown on an empty conversation.
  final List<String> suggestions;

  /// Localizable strings.
  final NeuralChatStrings strings;

  /// Show the orb header.
  final bool showHeader;

  /// Replaces the default empty state.
  final Widget? emptyState;

  /// Content width cap on large screens.
  final double maxContentWidth;

  /// Called with each submitted prompt (analytics, persistence).
  final ValueChanged<String>? onSubmitted;

  @override
  State<NeuralChatView> createState() => _NeuralChatViewState();
}

class _NeuralChatViewState extends State<NeuralChatView> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  int _lastCount = 0;

  NeuralAgent get _agent => widget.agent;

  @override
  void initState() {
    super.initState();
    _agent.addListener(_onAgent);
    _agent.streamingText.addListener(_autoScroll);
  }

  @override
  void didUpdateWidget(NeuralChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agent != widget.agent) {
      oldWidget.agent.removeListener(_onAgent);
      oldWidget.agent.streamingText.removeListener(_autoScroll);
      widget.agent.addListener(_onAgent);
      widget.agent.streamingText.addListener(_autoScroll);
    }
  }

  void _onAgent() {
    if (!mounted) return;
    setState(() {});
    if (_agent.messages.length != _lastCount) {
      _lastCount = _agent.messages.length;
      _autoScroll();
    }
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      // Follow the stream only if the user is already near the bottom.
      if (pos.maxScrollExtent - pos.pixels < 220) {
        if (reduceMotionOf(context)) {
          _scroll.jumpTo(pos.maxScrollExtent);
        } else {
          _scroll.animateTo(pos.maxScrollExtent,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut);
        }
      }
    });
  }

  @override
  void dispose() {
    _agent.removeListener(_onAgent);
    _agent.streamingText.removeListener(_autoScroll);
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit([String? value]) {
    final v = (value ?? _text.text).trim();
    if (v.isEmpty) return;
    _text.clear();
    widget.onSubmitted?.call(v);
    unawaited(_agent.send(v));
  }

  String _phaseText() => switch (_agent.phase) {
        NeuralAgentPhase.idle => 'Ready',
        NeuralAgentPhase.listening => widget.strings.listening,
        NeuralAgentPhase.thinking => widget.strings.thinking,
        NeuralAgentPhase.responding => 'Responding',
        NeuralAgentPhase.usingTool => 'Using ${_agent.activeTool ?? 'tools'}',
        NeuralAgentPhase.speaking => 'Speaking',
        NeuralAgentPhase.error => 'Something went wrong',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = _agent.messages;
    final visible = messages.where((m) => m.role != NeuralRole.tool).toList();
    final results = <String, NeuralToolResult>{
      for (final m in messages.where((m) => m.role == NeuralRole.tool))
        for (final r in m.parts.whereType<NeuralToolResult>()) r.callId: r,
    };
    final busy = _agent.isBusy;
    final empty = visible.isEmpty && !busy;

    final Widget content = Column(
      children: [
        if (widget.showHeader)
          _Header(
            agent: _agent,
            title: widget.title,
            subtitle: widget.subtitle ?? _phaseText(),
            compact: !empty,
          ),
        Expanded(
          child: empty
              ? (widget.emptyState ??
                  _EmptyState(
                    agent: _agent,
                    suggestions: widget.suggestions,
                    onPick: _submit,
                  ))
              : Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: visible.length + 1,
                    itemBuilder: (context, i) {
                      if (i == visible.length) {
                        return _Tail(agent: _agent, strings: widget.strings);
                      }
                      final m = visible[i];
                      return m.role == NeuralRole.user
                          ? _UserBubble(message: m)
                          : _AssistantMessage(
                              message: m,
                              results: results,
                              catalog: _agent.uiCatalog,
                              strings: widget.strings,
                              onAction: (a, d) => _agent.sendAction(a, d),
                            );
                    },
                  ),
                ),
        ),
        _Composer(
          controller: _text,
          focus: _focus,
          agent: _agent,
          strings: widget.strings,
          onSubmit: _submit,
        ),
      ],
    );

    return DefaultTextStyle.merge(
      style: TextStyle(color: theme.colorScheme.onSurface),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxContentWidth),
          child: content,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.agent,
    required this.title,
    required this.subtitle,
    required this.compact,
  });

  final NeuralAgent agent;
  final String? title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (!compact) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: agent.level,
            builder: (context, level, _) => NeuralOrb(
              size: 40,
              state: agent.orbState,
              level: level,
              semanticsLabel: 'Assistant status: $subtitle',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.agent,
    required this.suggestions,
    required this.onPick,
  });

  final NeuralAgent agent;
  final List<String> suggestions;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final orb = (c.maxHeight * 0.42).clamp(96.0, 220.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: agent.level,
                  builder: (context, level, _) =>
                      NeuralOrb(size: orb, state: agent.orbState, level: level),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in suggestions)
                      _GlassChip(label: s, onTap: () => onPick(s)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return Material(
      color: (dark ? Colors.white : Colors.black)
          .withValues(alpha: dark ? 0.07 : 0.04),
      shape: StadiumBorder(
        side: BorderSide(
            color: (dark ? Colors.white : Colors.black)
                .withValues(alpha: dark ? 0.12 : 0.08)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});
  final NeuralMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = NeuralPalette.of(context);
    final dark = palette.isDark;
    final images = message.parts.whereType<NeuralImagePart>().toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadiusDirectional.only(
                topStart: Radius.circular(20),
                topEnd: Radius.circular(20),
                bottomStart: Radius.circular(20),
                bottomEnd: Radius.circular(6),
              ).resolve(Directionality.of(context)),
              color: palette.isLiquid
                  ? (dark ? const Color(0xFF2A2C33) : const Color(0xFFEFF0F3))
                  : scheme.primaryContainer,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final img in images)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(img.bytes,
                            height: 140, fit: BoxFit.cover),
                      ),
                    ),
                  if (message.text.isNotEmpty)
                    SelectableText(message.text,
                        style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage({
    required this.message,
    required this.results,
    required this.catalog,
    required this.strings,
    required this.onAction,
  });

  final NeuralMessage message;
  final Map<String, NeuralToolResult> results;
  final NeuralUiCatalog? catalog;
  final NeuralChatStrings strings;
  final void Function(String, Map<String, Object?>) onAction;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final p in message.parts) {
      switch (p) {
        case NeuralReasoningPart():
          children.add(_Reasoning(text: p.text, title: strings.thought));
        case NeuralTextPart():
          if (p.text.trim().isNotEmpty) {
            children.add(NeuralMarkdownText(p.text));
          }
        case NeuralToolCall():
          if (catalog == null || p.name != catalog!.toolName) {
            children.add(
                _ToolChip(call: p, result: results[p.id], strings: strings));
          }
        case NeuralUiPart():
          if (catalog != null) {
            children.add(NeuralUiSurface(
                spec: p.spec, catalog: catalog!, onAction: onAction));
          }
        default:
          break;
      }
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Reasoning extends StatefulWidget {
  const _Reasoning({required this.text, required this.title});
  final String text;
  final String title;

  @override
  State<_Reasoning> createState() => _ReasoningState();
}

class _ReasoningState extends State<_Reasoning> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(widget.title,
                    style: t.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: reduceMotionOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding:
                const EdgeInsetsDirectional.only(start: 20, top: 2, bottom: 4),
            child: Text(widget.text,
                style: t.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45)),
          ),
        ),
      ],
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip(
      {required this.call, required this.result, required this.strings});
  final NeuralToolCall call;
  final NeuralToolResult? result;
  final NeuralChatStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = NeuralPalette.of(context);
    final failed = result?.isError ?? false;
    final done = result != null;
    final name = call.name.replaceAll('_', ' ');
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        label: done
            ? '${failed ? strings.toolFailed : strings.ranTool} $name'
            : 'Running $name',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: scheme.onSurface.withValues(alpha: 0.05),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  !done
                      ? Icons.more_horiz_rounded
                      : failed
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_rounded,
                  size: 16,
                  color: failed
                      ? palette.error
                      : (done ? palette.success : scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    done
                        ? '${failed ? strings.toolFailed : strings.ranTool} $name'
                        : name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The live end of the conversation: thinking shimmer, the streaming
/// answer, and error / refusal notices.
class _Tail extends StatelessWidget {
  const _Tail({required this.agent, required this.strings});
  final NeuralAgent agent;
  final NeuralChatStrings strings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final phase = agent.phase;
    final finish = agent.lastFinish?.reason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (phase == NeuralAgentPhase.listening)
          ValueListenableBuilder<String>(
            valueListenable: agent.liveTranscript,
            builder: (context, live, _) => Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(live.isEmpty ? strings.listening : live,
                  style: t.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ),
        if (phase == NeuralAgentPhase.thinking ||
            phase == NeuralAgentPhase.usingTool)
          ValueListenableBuilder<String>(
            valueListenable: agent.reasoningText,
            builder: (context, r, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: NeuralShimmerText(
                r.isEmpty ? strings.thinking : _lastLine(r),
              ),
            ),
          ),
        if (phase == NeuralAgentPhase.responding)
          ValueListenableBuilder<String>(
            valueListenable: agent.streamingText,
            builder: (context, s, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: NeuralMarkdownText(s, streaming: true),
            ),
          ),
        if (phase == NeuralAgentPhase.error)
          _Notice(
            icon: Icons.wifi_tethering_error_rounded,
            text: _errorText(agent.error),
            action: strings.retry,
            onAction: agent.retry,
            color: scheme.error,
          )
        else if (phase == NeuralAgentPhase.idle &&
            finish == NeuralFinishReason.refusal)
          _Notice(
            icon: Icons.shield_outlined,
            text: strings.refusal,
            action: strings.retry,
            onAction: agent.retry,
            color: scheme.onSurfaceVariant,
          )
        else if (phase == NeuralAgentPhase.idle &&
            finish == NeuralFinishReason.maxTokens)
          _Notice(
            icon: Icons.short_text_rounded,
            text: strings.truncated,
            color: scheme.onSurfaceVariant,
          ),
      ],
    );
  }

  static String _lastLine(String s) {
    final lines = s.trim().split('\n').where((l) => l.trim().isNotEmpty);
    final l = lines.isEmpty ? s : lines.last;
    return l.length > 140 ? '${l.substring(0, 140)}…' : l;
  }

  static String _errorText(Object? e) {
    if (e is NeuralModelException) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        return 'Authentication failed: check the API key.';
      }
      if (e.statusCode == 429) return 'Rate limited. Try again in a moment.';
      return e.message;
    }
    return '$e';
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.color,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String text;
  final Color color;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color)),
          ),
          if (action != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.agent,
    required this.strings,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final NeuralAgent agent;
  final NeuralChatStrings strings;
  final ValueChanged<String?> onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = NeuralPalette.of(context);
    final dark = palette.isDark;
    final busy = agent.isBusy;
    final listening = agent.phase == NeuralAgentPhase.listening;
    final canListen = agent.speechToText?.isAvailable ?? false;
    final field = listening
        ? ValueListenableBuilder<double>(
            valueListenable: agent.level,
            builder: (context, l, _) => NeuralWaveform(
                level: l, height: 44, semanticsLabel: strings.listening),
          )
        : CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () =>
                  onSubmit(null),
            },
            child: TextField(
              controller: controller,
              focusNode: focus,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.send,
              onSubmitted: onSubmit,
              decoration: InputDecoration(
                hintText: strings.hint,
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          );

    Widget button(IconData icon, String tip, VoidCallback onTap,
            {bool filled = false}) =>
        IconButton(
          tooltip: tip,
          onPressed: onTap,
          style: filled
              ? IconButton.styleFrom(
                  backgroundColor: scheme.onSurface,
                  foregroundColor: scheme.surface,
                )
              : null,
          icon: Icon(icon),
        );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: NeuralEdgeGlow(
          active: busy,
          level: agent.level.value,
          borderRadius: 28,
          width: 14,
          child: Material(
            color: dark ? const Color(0xFF1E2027) : Colors.white,
            elevation: dark ? 0 : 3,
            shadowColor: Colors.black.withValues(alpha: 0.18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(
                  color: (dark ? Colors.white : Colors.black)
                      .withValues(alpha: dark ? 0.1 : 0.06)),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 4, 6, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: field),
                  if (canListen && !busy)
                    button(Icons.mic_none_rounded, strings.speak,
                        () => agent.listen()),
                  if (busy)
                    button(Icons.stop_rounded, strings.stop, agent.stop,
                        filled: true)
                  else
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => AnimatedOpacity(
                        opacity: controller.text.trim().isEmpty ? 0.35 : 1,
                        duration: const Duration(milliseconds: 150),
                        child: button(Icons.arrow_upward_rounded, strings.send,
                            () => onSubmit(null),
                            filled: true),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight Markdown for chat answers: headings (`#`), bullets
/// (`-`, `*`, `1.`), `**bold**`, `*italic*` and `` `code` ``. Selectable.
/// With [streaming], a soft caret marks the live end.
class NeuralMarkdownText extends StatelessWidget {
  /// Renders [text].
  const NeuralMarkdownText(this.text, {super.key, this.streaming = false});

  /// Markdown-ish text.
  final String text;

  /// Show the live caret.
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final base = t.bodyLarge?.copyWith(height: 1.5) ?? const TextStyle();
    final lines = text.split('\n');
    final blocks = <Widget>[];
    var inCode = false;
    final code = StringBuffer();
    for (final raw in lines) {
      if (raw.trimLeft().startsWith('```')) {
        if (inCode) {
          blocks.add(_CodeBlock(code.toString().trimRight()));
          code.clear();
        }
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        code.writeln(raw);
        continue;
      }
      final line = raw.trimRight();
      if (line.isEmpty) {
        blocks.add(const SizedBox(height: 6));
        continue;
      }
      final h = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
      final b = RegExp(r'^\s*([-*•]|\d+\.)\s+(.*)$').firstMatch(line);
      if (h != null) {
        final level = h.group(1)!.length;
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text.rich(
            _inline(
                h.group(2)!,
                (level == 1 ? t.titleLarge : t.titleMedium)!
                    .copyWith(fontWeight: FontWeight.w700),
                scheme),
          ),
        ));
      } else if (b != null) {
        final marker = b.group(1)!;
        blocks.add(Padding(
          padding:
              const EdgeInsetsDirectional.only(start: 4, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(marker.endsWith('.') ? marker : '•',
                    style: base.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Expanded(child: Text.rich(_inline(b.group(2)!, base, scheme))),
            ],
          ),
        ));
      } else {
        blocks.add(Text.rich(_inline(line, base, scheme)));
      }
    }
    if (inCode && code.isNotEmpty) {
      blocks.add(_CodeBlock(code.toString().trimRight()));
    }
    if (streaming) blocks.add(const _Caret());
    return SelectionArea(
      child: Semantics(
        liveRegion: streaming,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: blocks),
      ),
    );
  }

  static TextSpan _inline(String s, TextStyle base, ColorScheme scheme) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`|\*[^*\s][^*]*\*)');
    var i = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > i) spans.add(TextSpan(text: s.substring(i, m.start)));
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        spans.add(TextSpan(
            text: tok.substring(2, tok.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (tok.startsWith('`')) {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Menlo', 'Consolas', 'Roboto Mono'],
            backgroundColor: scheme.onSurface.withValues(alpha: 0.07),
          ),
        ));
      } else {
        spans.add(TextSpan(
            text: tok.substring(1, tok.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      i = m.end;
    }
    if (i < s.length) spans.add(TextSpan(text: s.substring(i)));
    return TextSpan(style: base, children: spans);
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.code);
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(code,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Menlo', 'Consolas', 'Roboto Mono'],
                height: 1.45)),
      ),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _c.value = 1;
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = NeuralPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: FadeTransition(
        opacity: Tween(begin: 0.25, end: 1.0).animate(_c),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: palette.strokeColors),
          ),
        ),
      ),
    );
  }
}

/// Text with a soft light sweeping across it: the "thinking" label.
class NeuralShimmerText extends StatefulWidget {
  /// Creates shimmering [text].
  const NeuralShimmerText(this.text, {super.key, this.style});

  /// The label.
  final String text;

  /// Text style (defaults to `bodyMedium`).
  final TextStyle? style;

  @override
  State<NeuralShimmerText> createState() => _NeuralShimmerTextState();
}

class _NeuralShimmerTextState extends State<NeuralShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = NeuralPalette.of(context);
    final style = (widget.style ??
            Theme.of(context).textTheme.bodyMedium ??
            const TextStyle())
        .copyWith(color: Colors.white);
    final dim = scheme.onSurfaceVariant.withValues(alpha: 0.55);
    return Semantics(
      label: widget.text,
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final x = _c.value * 3 - 1;
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment(x - 1, 0),
                end: Alignment(x + 1, 0),
                colors: [dim, palette.strokeAt(0.6), dim],
                stops: const [0.3, 0.5, 0.7],
              ).createShader(r),
              child: child,
            );
          },
          child: Text(widget.text, style: style),
        ),
      ),
    );
  }
}
