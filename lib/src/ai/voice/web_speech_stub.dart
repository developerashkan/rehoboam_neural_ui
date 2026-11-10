// Non-web platforms: the Web Speech API does not exist.

/// Speech recognition placeholder.
class WebRecognizer {
  /// Always false off the web.
  bool get isAvailable => false;

  /// Throws: not available.
  Stream<(String, bool)> listen(String? localeId) => Stream.error(
      UnsupportedError('Web Speech recognition is only available on the web'));

  /// No-op.
  void stop() {}

  /// No levels.
  Stream<double> get levels => const Stream.empty();
}

/// Speech synthesis placeholder.
class WebSynth {
  /// Always false off the web.
  bool get isAvailable => false;

  /// Throws: not available.
  Stream<int> speak(String text, String? localeId, double rate, double pitch) =>
      Stream.error(UnsupportedError(
          'Web Speech synthesis is only available on the web'));

  /// No-op.
  void stop() {}
}
