# rehoboam_neural_ui

A high-fidelity, organic "Rehoboam" style neural HUD and data-visualization widget for Flutter.

<p align="center">
  <img src="https://raw.githubusercontent.com/developerashkan/rehoboam_neural_ui/main/assets/Screenshot.png" width="48%" alt="Screenshot" />
  <img src="https://raw.githubusercontent.com/developerashkan/rehoboam_neural_ui/main/assets/rehoboam_screen_record.gif" width="48%" alt="Demo" />
</p>

## Features

- **Organic Animation**: Grainy, particulate spiky ring that reacts to audio or data levels.
- **Geographic Mapping**: Project 3D Latitude/Longitude coordinates onto the 2D rotating globe HUD.
- **Divergence Spikes**: Visualizes "divergences" in data with sharp, organic spikes.
- **Technical HUD**: Integrated labels and leader lines for a sci-fi look.
- **Performance Optimized**: Uses custom path rendering and `CustomPainter` for smooth 60fps animations.

## Usage

```dart
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';

// ...

AiThinkingAnimation(
  size: 320,
  level: _micLevel, // 0.0 to 1.0
  mode: AiFaceMode.listening,
  centerLabel: 'AI',
  topLabel: 'SCANNING...',
  bottomLabel: 'TOKYO, JP',
  targetLat: 35.6762,
  targetLon: 139.6503,
)
```

## Additional Widgets

- `VoiceWave`: A vector-based audio reactive waveform.
- `WordByWordTranscript`: A stylized text widget for displaying live transcription results.
