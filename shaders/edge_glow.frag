// rehoboam_neural_ui :: assistant edge glow.
//
// A band of iridescent light hugging the inside of a rounded rectangle,
// flowing along the perimeter and breathing with the voice level. Used to
// show "the assistant is active" around a screen, card or input.
#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;       // 0-1
uniform float uPhase;     // 2
uniform float uLevel;     // 3
uniform float uActive;    // 4  0..1 eased visibility
uniform float uRadius;    // 5  corner radius px
uniform float uWidth;     // 6  glow width px
uniform vec4 uC0;         // 7-10
uniform vec4 uC1;         // 11-14
uniform vec4 uC2;         // 15-18
uniform vec4 uC3;         // 19-22

out vec4 fragColor;

const float TAU = 6.28318530718;

float sdRoundRect(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + vec2(r);
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 cyc(float s) {
  float x = fract(s) * 4.0;
  if (x < 1.0) return mix(uC0.rgb, uC1.rgb, smoothstep(0.0, 1.0, x));
  if (x < 2.0) return mix(uC1.rgb, uC2.rgb, smoothstep(0.0, 1.0, x - 1.0));
  if (x < 3.0) return mix(uC2.rgb, uC3.rgb, smoothstep(0.0, 1.0, x - 2.0));
  return mix(uC3.rgb, uC0.rgb, smoothstep(0.0, 1.0, x - 3.0));
}

void main() {
  if (uActive <= 0.001) {
    fragColor = vec4(0.0);
    return;
  }
  vec2 frag = FlutterFragCoord().xy;
  vec2 c = 0.5 * uSize;
  vec2 p = frag - c;
  float r = clamp(uRadius, 0.0, min(c.x, c.y));
  float d = sdRoundRect(p, c, r);          // <= 0 inside
  float inside = -d;
  if (inside < -1.0) {
    fragColor = vec4(0.0);
    return;
  }
  float t = uPhase;
  // Perimeter coordinate from the angle, warped so colour flows unevenly.
  float ang = atan(p.y / max(c.y, 1.0), p.x / max(c.x, 1.0)) / TAU;
  float flow = ang + t * 0.07 + 0.06 * sin(ang * TAU * 2.0 + t * 0.9);
  vec3 col = cyc(flow);

  // Width breathes with the level and varies along the edge.
  float wv = uWidth * (0.7 + 0.5 * uLevel) * (0.8 + 0.35 * sin(ang * TAU * 3.0 - t * 1.3));
  float band = exp(-max(inside, 0.0) / max(wv, 1.0));
  float line = exp(-pow(max(inside, 0.0) / 1.6, 2.0));
  float a = clamp((band * (0.55 + 0.35 * uLevel) + line * 0.6) * uActive, 0.0, 1.0);
  a *= smoothstep(-1.0, 0.5, inside);       // anti-aliased outer edge
  col = mix(col, vec3(1.0), line * 0.35);
  fragColor = vec4(col * a, a);
}
