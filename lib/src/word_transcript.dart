import 'package:flutter/material.dart';

/// A live, word-by-word transcription display.
///
/// Words appear one at a time as they are recognized (partials stream in),
/// with a smooth fade/slide entrance. The latest word pulses with a soft
/// highlight until the next word (or the final transcript) arrives.
/// Fully theme-aware, Material 3, and cheap: only text widgets + one
/// [AnimatedOpacity] — no per-frame work.
class WordByWordTranscript extends StatefulWidget {
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
  });

  /// The current partial (or final) transcript.
  final String text;

  /// When true, the transcript is complete (no more words coming).
  final bool isFinal;

  final TextStyle? textStyle;
  final int maxLines;
  final Color? highlightColor;
  final Duration animationDuration;
  final double wordSpacing;

  /// The index of the word currently being spoken/highlighted.
  final int? highlightIndex;

  @override
  State<WordByWordTranscript> createState() => _WordByWordTranscriptState();
}

class _WordByWordTranscriptState extends State<WordByWordTranscript> {
  final List<_Word> _words = [];
  String _lastText = '';

  @override
  void didUpdateWidget(WordByWordTranscript old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    if (widget.text == _lastText) return;
    final oldText = _lastText;
    _lastText = widget.text;
    final incoming = widget.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    // If this is a new utterance (text reset), start fresh.
    if (incoming.isEmpty) {
      setState(() => _words.clear());
      return;
    }

    // DETECTION: Is this a continuation or a completely new text?
    // If the new text does not start with the old text, it's a replacement (e.g. Response replacing Transcript).
    final isReplacement =
        !widget.text.toLowerCase().startsWith(oldText.trim().toLowerCase());

    if (isReplacement) {
      setState(() {
        _words.clear();
        final now = DateTime.now();
        for (final w in incoming) {
          _words.add(_Word(w, now));
        }
      });
      return;
    }

    // Grow word list to match; keep stable words, append new ones.
    final now = DateTime.now();
    setState(() {
      for (var i = _words.length; i < incoming.length; i++) {
        _words.add(_Word(incoming[i], now));
      }
      // If the last word changed (recognition corrected it), update it.
      if (_words.isNotEmpty && incoming.isNotEmpty) {
        _words.last.text = incoming.last;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.textStyle ?? Theme.of(context).textTheme.headlineSmall;
    final highlight = widget.highlightColor ?? scheme.primary;
    final baseColor = style?.color ?? scheme.onSurface;

    return Wrap(
      spacing: widget.wordSpacing,
      runSpacing: 2,
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < _words.length; i++)
          _WordChip(
            word: _words[i],
            isLast: i == _words.length - 1,
            isHighlighted: widget.highlightIndex == i,
            isFinal: widget.isFinal,
            style: style,
            highlight: highlight,
            baseColor: baseColor,
            duration: widget.animationDuration,
          ),
      ],
    );
  }
}

class _Word {
  _Word(this.text, this.born);
  String text;
  final DateTime born;
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.word,
    required this.isLast,
    required this.isHighlighted,
    required this.isFinal,
    required this.style,
    required this.highlight,
    required this.baseColor,
    required this.duration,
  });

  final _Word word;
  final bool isLast;
  final bool isHighlighted;
  final bool isFinal;
  final TextStyle? style;
  final Color highlight;
  final Color baseColor;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final active = isHighlighted || (isLast && !isFinal && !isHighlighted);

    // Fade/slide in once when the word is born.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 150),
        style: (style ??
                Theme.of(context).textTheme.headlineSmall ??
                const TextStyle())
            .copyWith(
          color: active ? highlight : baseColor.withValues(alpha: 0.4),
          fontWeight: active ? FontWeight.w800 : style?.fontWeight,
          fontSize: (style?.fontSize ?? 24) * (active ? 1.1 : 1.0),
        ),
        child: Text(
          word.text,
        ),
      ),
    );
  }
}
