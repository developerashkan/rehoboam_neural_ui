import 'package:flutter/material.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RehoboamDemo(),
  ));
}

class RehoboamDemo extends StatefulWidget {
  const RehoboamDemo({super.key});

  @override
  State<RehoboamDemo> createState() => _RehoboamDemoState();
}

class _RehoboamDemoState extends State<RehoboamDemo> {
  final double _level = 0.5; // Fixed load for demo
  HudMode _mode = HudMode.ring;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Center(
        child: GestureDetector(
          onTap: () => setState(() =>
              _mode = _mode == HudMode.ring ? HudMode.earth : HudMode.ring),
          child: AiThinkingAnimation(
            size: 380,
            level: _level,
            hudMode: _mode,
            centerLabel: 'NEURAL',
            topLabel: 'REHOBOAM V1.0',
            bottomLabel:
                _mode == HudMode.earth ? 'WORLD SCAN ACTIVE' : 'SYSTEM IDLE',
            targetLat: 34.0522,
            targetLon: -118.2437,
          ),
        ),
      ),
    );
  }
}
