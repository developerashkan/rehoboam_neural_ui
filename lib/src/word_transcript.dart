import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core/neural_clock.dart';

/// A live, word-by-word transcription display.
///
/// Words fade and slide in as recognition partials stream in. Only words
/// that actually changed re-animate: when the recognizer revises an earlier
/// word, drops one, or the text is replaced entirely, the display diffs the
/// word lists instead of appending blindly. The latest word (or
/// [highlightIndex]) is emphasized until [isFinal].
///
/// The whole transcript is exposed to screen readers as one live region,
/// and [maxLines] keeps the newest lines visible.
class WordByWordTranscript extends StatefulWidget {
  /// Creates a transcript.
  const WordByWordTranscript({
    super.key,
    this.text = '',
    this.isFinal = false,
    this.textStyle,
    this.maxLines = 3,
    this.highlightColor,
    this.animationDuration = const Duration(milliseconds: 260),
    this.wordSpacing = 6,
    this.highlightIndex,
    this.textAlign = WrapAlignment.center,
  });

  /// The current partial (or final) transcript.
  final String text;

  /// When true, the transcript is complete (no more words coming).
  final bool isFinal;

  /// Base text style. Defaults to `headlineSmall`.
  final TextStyle? textStyle;

  /// Maximum visible lines; older lines scroll out of view. `null` or `0`
  /// shows everything.
  final int? maxLines;

  /// Emphasis color. Defaults to `primary`.
  final Color? highlightColor;

  /// Entrance animation length (zero when animations are disabled).
  final Duration animationDuration;

  /// Horizontal gap between words.
  final double wordSpacing;

  /// The index of the word currently being spoken/highlighted.
  final int? highlightIndex;

  /// Line alignment (start / center / end follow the text direction).
  final WrapAlignment textAlign;

  @override
  State<WordByWordTranscript> createState() => _WordByWordTranscriptState();
}

class _WordByWordTranscriptState extends State<WordByWordTranscript> {
  final List<_Word> _words = [];
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(WordByWordTranscript old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _sync();
  }

  /// Splits [text] into words (any run of whitespace separates).
  static List<String> split(String text) => text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList(growable: false);

  void _sync() {
    // Called from initState / didUpdateWidget, which rebuild anyway: no
    // setState needed (and none after dispose).
    final incoming = split(widget.text);
    // Keep the longest common prefix (case-insensitive) so stable words do
    // not flash; everything after the first difference is re-created with
    // fresh keys so it animates in.
    var keep = 0;
    final limit = math.min(_words.length, incoming.length);
    while (keep < limit &&
        _words[keep].text.toLowerCase() == incoming[keep].toLowerCase()) {
      keep++;
    }
    // A recognizer correction of the *last* word only (e.g. "wor" ->
    // "world") updates it in place instead of re-animating it.
    final lastCorrection = keep == _words.length - 1 &&
        incoming.length >= _words.length &&
        incoming[keep]
            .toLowerCase()
            .startsWith(_words[keep].text.toLowerCase());
    if (lastCorrection) {
      _words[keep].text = incoming[keep];
      keep++;
    }
    for (var i = 0; i < keep; i++) {
      _words[i].text = incoming[i];
    }
    _words.removeRange(keep, _words.length);
    for (var i = keep; i < incoming.length; i++) {
      _words.add(_Word(incoming[i], _nextId++));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style =
        widget.textStyle ?? theme.textTheme.headlineSmall ?? const TextStyle();
    final highlight = widget.highlightColor ?? scheme.primary;
    final baseColor = style.color ?? scheme.onSurface;
    final duration =
        reduceMotionOf(context) ? Duration.zero : widget.animationDuration;

    Widget wrap = Wrap(
      spacing: widget.wordSpacing,
      runSpacing: 2,
      alignment: widget.textAlign,
      children: [
        for (var i = 0; i < _words.length; i++)
          _WordChip(
            key: ValueKey(_words[i].id),
            text: _words[i].text,
            active: widget.highlightIndex != null
                ? widget.highlightIndex == i
                : (i == _words.length - 1 && !widget.isFinal),
            style: style,
            highlight: highlight,
            baseColor: baseColor,
            duration: duration,
          ),
      ],
    );

    final maxLines = widget.maxLines;
    if (maxLines != null && maxLines > 0) {
      final scaler = MediaQuery.textScalerOf(context);
      final fontSize = style.fontSize ?? 24;
      final lineHeight =
          scaler.scale(fontSize) * (style.height ?? 1.25) + 2; // + runSpacing
      wrap = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: lineHeight * maxLines + 4),
        child: ClipRect(
          child: SingleChildScrollView(
            reverse: true, // newest line stays visible
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(width: double.infinity, child: wrap),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: _words.map((w) => w.text).join(' '),
      child: ExcludeSemantics(child: wrap),
    );
  }
}

class _Word {
  _Word(this.text, this.id);
  String text;
  final int id;
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    super.key,
    required this.text,
    required this.active,
    required this.style,
    required this.highlight,
    required this.baseColor,
    required this.duration,
  });

  final String text;
  final bool active;
  final TextStyle style;
  final Color highlight;
  final Color baseColor;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    // Emphasis uses a transform, not a bigger font, so the line never
    // reflows when the highlighted word moves on.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: AnimatedScale(
        scale: active ? 1.08 : 1.0,
        duration: duration == Duration.zero
            ? Duration.zero
            : const Duration(milliseconds: 150),
        child: AnimatedDefaultTextStyle(
          duration: duration == Duration.zero
              ? Duration.zero
              : const Duration(milliseconds: 150),
          style: style.copyWith(
            color: active ? highlight : baseColor.withValues(alpha: 0.4),
            fontWeight: active ? FontWeight.w800 : style.fontWeight,
          ),
          child: Text(text),
        ),
      ),
    );
  }
}
