// rehoboam_neural_ui :: liquid glass rim.
//
// Drawn over a blurred backdrop: the light catching the thick edge of a
// glass slab. A bright, thin top-left rim; a prismatic fringe where the
// edge bends light; a faint inner shade at the bottom; a slow sheen.
#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;      // 0-1
uniform float uPhase;    // 2
uniform float uRadius;   // 3
uniform float uDark;     // 4   1 on dark themes
uniform float uDisp;     // 5   prismatic strength
uniform float uHover;    // 6   0..1 emphasis
uniform vec2 uLight;     // 7-8 light direction (unit, y down)

out vec4 fragColor;

const float TAU = 6.28318530718;

float sdRoundRect(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + vec2(r);
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 spectrum(float t) {
  return clamp(0.5 + 0.5 * cos(TAU * (t + vec3(0.0, 0.33, 0.67))), 0.0, 1.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 c = 0.5 * uSize;
  vec2 p = frag - c;
  float r = clamp(uRadius, 0.0, min(c.x, c.y));
  float d = sdRoundRect(p, c - 0.5, r);
  float inside = -d;
  if (inside < -0.5) {
    fragColor = vec4(0.0);
    return;
  }
  // Outward normal of the rounded rect.
  vec2 inner = c - vec2(r);
  vec2 q = p - clamp(p, -inner, inner);
  float ql = length(q);
  vec2 n = ql > 0.001 ? q / ql : normalize(p / max(c, vec2(1.0)) + vec2(1e-4));

  float facing = dot(n, -uLight);          // 1 where the light hits the rim
  float rim = exp(-max(inside, 0.0) / 1.1);  // thin bright edge
  float body = exp(-max(inside, 0.0) / 9.0); // thicker refracted band

  float lit = smoothstep(-0.2, 1.0, facing);
  vec3 col = vec3(1.0) * rim * (0.35 + 0.55 * lit) * (0.8 + 0.4 * uHover);
  float ang = atan(n.y, n.x) / TAU;
  // Integer multiple of the angle: seamless across atan()'s +-pi jump.
  vec3 prism = spectrum(ang * 2.0 + uPhase * 0.03 + inside * 0.04);
  col += prism * body * uDisp * (0.18 + 0.22 * lit) * (0.8 + 0.6 * uHover);

  // Bottom inner shade gives the slab thickness.
  float shade = smoothstep(-0.3, -1.0, facing) * body * (uDark > 0.5 ? 0.25 : 0.12);

  // Slow diagonal sheen across the face.
  vec2 uv = frag / uSize;
  float sheenPos = fract(uPhase * 0.05) * 3.0 - 1.0;
  float sx = (uv.x + uv.y * 0.6 - sheenPos) / 0.12; // signed: square, never pow
  float sheen = exp(-sx * sx) * 0.05 * (0.5 + uHover);

  float a = clamp(rim * 0.7 + body * uDisp * 0.25 + shade + sheen, 0.0, 1.0);
  a *= smoothstep(-0.5, 0.5, inside);
  vec3 outc = col + vec3(sheen);
  // Shade is dark: blend it in via alpha with no added light.
  fragColor = vec4(clamp(outc, 0.0, 1.0) * a * (1.0 - shade * 0.8), a);
}
