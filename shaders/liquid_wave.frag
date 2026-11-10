// rehoboam_neural_ui :: liquid waveform.
//
// Four translucent ribbons of light, pinned at both ends, whose amplitude
// follows the voice level. Overlapping ribbons add up like light, so the
// crossings bloom white. Transparent background.
#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;     // 0-1
uniform float uPhase;   // 2  flow phase (never wraps)
uniform float uLevel;   // 3  smoothed level 0..1
uniform float uIdle;    // 4  resting amplitude
uniform vec4 uC0;       // 5-8
uniform vec4 uC1;       // 9-12
uniform vec4 uC2;       // 13-16
uniform vec4 uC3;       // 17-20
uniform float uLight;   // 21 1 on dark backgrounds, 0 on light ones

out vec4 fragColor;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float x = uv.x * 2.0 - 1.0;            // -1..1
  float y = (uv.y - 0.5) * 2.0;          // -1..1, centred
  float env = pow(max(0.0, 1.0 - x * x), 1.6); // pinned ends
  float amp = min(0.92, uIdle + 1.15 * uLevel) * env;
  float px = 2.0 / uSize.y;              // one pixel in y units
  float t = uPhase;

  vec3 acc = vec3(0.0);
  float alpha = 0.0;
  for (int i = 0; i < 4; i++) {
    float fi = float(i);
    vec3 c = i == 0 ? uC0.rgb : (i == 1 ? uC1.rgb : (i == 2 ? uC2.rgb : uC3.rgb));
    float k = 2.2 + fi * 0.9;
    float sp = 1.1 + fi * 0.45;
    float a = amp * (0.9 - fi * 0.16);
    float yi = a * sin(k * x + t * sp + fi * 1.7) * (0.75 + 0.25 * sin(t * 0.6 + fi));
    float dist = abs(y - yi);
    float thick = px * (1.1 + 1.1 * uLevel);
    float dl = dist / thick;
    float line = exp(-dl * dl);
    float glow = exp(-dist / (px * (5.0 + 10.0 * uLevel))) * 0.3;
    // A ribbon also fills softly toward the centre line, like a membrane.
    float fill = (sign(yi) * y > 0.0 && abs(y) < abs(yi)) ? 0.09 * env : 0.0;
    float v = line + glow * (0.6 + 0.4 * uLevel) + fill;
    acc += c * v;
    alpha += v * 0.7;
  }
  // Additive light reads well on dark; on light backgrounds deepen instead.
  // Soft tone mapping keeps each ribbon's hue where they overlap instead
  // of clipping everything to white.
  float a = 1.0 - exp(-alpha);
  vec3 col = (1.0 - exp(-acc * 1.2)) * mix(0.85, 1.0, uLight);
  col = min(col, vec3(a));
  fragColor = vec4(col, a);
}
