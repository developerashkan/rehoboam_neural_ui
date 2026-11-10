// Web: the browser's Web Speech API through dart:js_interop (no plugin).
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? _ctor(String a, String b) {
  final g = globalContext;
  final v = g.getProperty<JSAny?>(a.toJS) ?? g.getProperty<JSAny?>(b.toJS);
  return v.isA<JSFunction>() ? v as JSObject : null;
}

/// Wraps `SpeechRecognition` / `webkitSpeechRecognition`.
class WebRecognizer {
  JSObject? _rec;
  final StreamController<double> _levels = StreamController.broadcast();

  /// Whether the browser supports recognition.
  bool get isAvailable =>
      _ctor('SpeechRecognition', 'webkitSpeechRecognition') != null;

  /// Live levels (synthesized from recognition activity).
  Stream<double> get levels => _levels.stream;

  /// Listens once; emits (text, isFinal).
  Stream<(String, bool)> listen(String? localeId) {
    final out = StreamController<(String, bool)>();
    final ctor = _ctor('SpeechRecognition', 'webkitSpeechRecognition');
    if (ctor == null) {
      out.addError(UnsupportedError('Speech recognition is not supported'));
      out.close();
      return out.stream;
    }
    final rec = (ctor as JSFunction).callAsConstructor<JSObject>();
    _rec = rec;
    rec['interimResults'] = true.toJS;
    rec['continuous'] = false.toJS;
    if (localeId != null) rec['lang'] = localeId.toJS;
    var latest = '';
    rec['onresult'] = ((JSObject ev) {
      final results = ev['results'] as JSObject;
      final n = (results['length'] as JSNumber).toDartInt;
      final buf = StringBuffer();
      var isFinal = false;
      for (var i = 0; i < n; i++) {
        final r = results.callMethod<JSObject>('item'.toJS, i.toJS);
        final alt = r.callMethod<JSObject>('item'.toJS, 0.toJS);
        buf.write((alt['transcript'] as JSString).toDart);
        isFinal = (r['isFinal'] as JSBoolean).toDart;
      }
      latest = buf.toString();
      _levels.add(0.4 + (latest.length % 7) / 12);
      if (!out.isClosed) out.add((latest, isFinal));
    }).toJS;
    rec['onerror'] = ((JSObject ev) {
      final code = (ev['error'] as JSString?)?.toDart ?? 'error';
      if (!out.isClosed && code != 'no-speech' && code != 'aborted') {
        out.addError(StateError('Speech recognition: $code'));
      }
    }).toJS;
    rec['onend'] = (() {
      _levels.add(0);
      if (!out.isClosed) {
        out.add((latest, true));
        out.close();
      }
    }).toJS;
    rec.callMethod<JSAny?>('start'.toJS);
    return out.stream;
  }

  /// Stops listening.
  void stop() => _rec?.callMethod<JSAny?>('stop'.toJS);
}

/// Wraps `speechSynthesis`.
class WebSynth {
  JSObject? get _synth =>
      globalContext.getProperty<JSObject?>('speechSynthesis'.toJS);

  /// Whether the browser supports synthesis.
  bool get isAvailable =>
      _synth != null &&
      _ctor('SpeechSynthesisUtterance', 'SpeechSynthesisUtterance') != null;

  /// Speaks; emits the character index of each word boundary.
  Stream<int> speak(String text, String? localeId, double rate, double pitch) {
    final out = StreamController<int>();
    final ctor = _ctor('SpeechSynthesisUtterance', 'SpeechSynthesisUtterance');
    final synth = _synth;
    if (ctor == null || synth == null) {
      out.addError(UnsupportedError('Speech synthesis is not supported'));
      out.close();
      return out.stream;
    }
    final u = (ctor as JSFunction).callAsConstructor<JSObject>(text.toJS);
    u['rate'] = rate.toJS;
    u['pitch'] = pitch.toJS;
    if (localeId != null) u['lang'] = localeId.toJS;
    u['onboundary'] = ((JSObject ev) {
      final i = (ev['charIndex'] as JSNumber?)?.toDartInt ?? 0;
      if (!out.isClosed) out.add(i);
    }).toJS;
    void done() {
      if (!out.isClosed) out.close();
    }

    u['onend'] = (() => done()).toJS;
    u['onerror'] = (() => done()).toJS;
    out.add(0);
    synth.callMethod<JSAny?>('speak'.toJS, u);
    return out.stream;
  }

  /// Stops speaking.
  void stop() => _synth?.callMethod<JSAny?>('cancel'.toJS);
}
