/// Rehoboam neural UI for Flutter: a pure liquid-glass design system
/// (assistant orb, voice waveform, edge glow, glass), the organic Rehoboam
/// HUD ring and 3D globe, gauges, charts, heatmaps, scan rings, presence
/// avatars, and an AI layer (any LLM, tools, generative UI, voice, chat).
library;

export 'ai.dart';
export 'src/core/neural_theme.dart'
    show NeuralThemeData, NeuralPalette, NeuralDesign, NeuralSpectrum;
export 'src/liquid/liquid_orb.dart' show NeuralLiquidOrb, LiquidPalette;
export 'src/liquid/liquid_widgets.dart'
    show NeuralWaveform, NeuralEdgeGlow, LiquidGlassRim;
export 'src/liquid/neural_shaders.dart' show NeuralShaders, NeuralShader;
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
