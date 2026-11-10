/// Rehoboam-style neural UI for Flutter: an organic HUD ring with a 3D
/// globe, plus assistant orbs, voice visuals, gauges, glowing charts,
/// heatmaps, glass cards, scan rings, presence avatars and a living
/// network backdrop. Pure Flutter, every platform.
library;

export 'src/core/neural_theme.dart' show NeuralThemeData, NeuralPalette;
export 'src/rehoboam.dart' show AiThinkingAnimation, AiFaceMode, HudMode;
export 'src/voice_wave.dart'
    show VoiceWave, VoiceWaveMode, AudioLevelSnapshot, AudioLevelStream;
export 'src/widgets/neural_avatar.dart' show NeuralAvatar, NeuralPresence;
export 'src/widgets/neural_gauge.dart' show NeuralGauge, NeuralGaugeThreshold;
export 'src/widgets/neural_glass_card.dart' show NeuralGlassCard;
export 'src/widgets/neural_heatmap.dart' show NeuralHeatmap;
export 'src/widgets/neural_network_background.dart'
    show NeuralNetworkBackground;
export 'src/widgets/neural_orb.dart' show NeuralOrb, NeuralOrbState;
export 'src/widgets/neural_progress.dart'
    show NeuralProgress, NeuralProgressShape;
export 'src/widgets/neural_scan_ring.dart'
    show NeuralScanRing, NeuralScanStatus;
export 'src/widgets/neural_sparkline.dart' show NeuralSparkline;
export 'src/word_transcript.dart' show WordByWordTranscript;
