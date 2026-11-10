// rehoboam_neural_ui :: liquid glass orb.
//
// A glass sphere holding two immiscible fluids. Their interface is a
// flowing wave; light splitting through it draws a prismatic band, the rim
// shows a chromatic fringe, and the lower fluid glows with transmitted
// light. Everything is analytic (no textures), so it is crisp at any size.
#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;     // 0-1   widget size in pixels
uniform float uPhase;   // 2     flow phase (seconds, state-scaled, never wraps)
uniform float uAngle;   // 3     accumulated swirl angle (radians)
uniform float uLevel;   // 4     smoothed audio level 0..1
uniform float uAmp;     // 5     interface amplitude
uniform float uDisp;    // 6     dispersion strength 0..1.5
uniform float uGlow;    // 7     transmitted-light strength
uniform vec4 uTop;      // 8-11  upper fluid
uniform vec4 uBottom;   // 12-15 lower fluid
uniform vec4 uRim;      // 16-19 rim light tint
uniform float uScale;   // 20    orb radius as a fraction of the half-size

out vec4 fragColor;

const float TAU = 6.28318530718;

// Gaussian bump. Never pow() a signed value: pow(x, y) is undefined for
// x < 0 in GLSL and some backends return garbage.
float bump(float x) { return exp(-x * x); }

vec3 spectrum(float t) {
  return clamp(0.5 + 0.5 * cos(TAU * (t + vec3(0.0, 0.33, 0.67))), 0.0, 1.0);
}

mat2 rot(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat2(c, -s, s, c);
}

float wave(float x, float t, float amp, float lv) {
  return amp * (0.62 * sin(1.7 * x + t * 0.9)
              + 0.28 * sin(3.3 * x - t * 1.35 + 1.3)
              + (0.10 + 0.30 * lv) * sin(6.1 * x + t * 2.4 + 0.4))
         - 0.05;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float R = 0.5 * min(uSize.x, uSize.y) * uScale;
  vec2 p = (frag - 0.5 * uSize) / R; // unit disc, y down
  float d = length(p);
  float aa = 1.6 / R;
  float mask = 1.0 - smoothstep(1.0 - aa, 1.0 + aa * 0.25, d);
  if (mask <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  float z = sqrt(max(0.0, 1.0 - d * d));
  // Refraction: the ball magnifies toward its rim.
  vec2 q = p / (0.6 + 0.4 * z);
  q = rot(uAngle) * q;
  float t = uPhase;

  float s = q.y - wave(q.x, t, uAmp, uLevel);
  float w = 0.012 + 0.03 * (1.0 - z);
  float lower = smoothstep(-w, w, s);

  // Upper fluid: deep at the crown, lifting toward the interface.
  vec3 top = uTop.rgb * (0.42 + 0.7 * smoothstep(-1.35, 0.3, q.y));
  top += 0.12 * bump((s + 0.14) / 0.13) * mix(uTop.rgb, vec3(1.0), 0.7);

  // Lower fluid: bright, shaded right under the interface.
  // Mercury: deep just under the interface, brightening toward the base.
  vec3 bot = uBottom.rgb * (0.5 + 0.42 * smoothstep(-0.05, 1.05, q.y));
  bot = mix(bot * 0.72, bot, smoothstep(0.0, 0.3, s));
  bot += 0.08 * sin(q.x * 3.0 + t * 0.4) * smoothstep(0.1, 0.7, s) * uBottom.rgb;
  float transmit = exp(-pow(length((p - vec2(0.05, 0.8)) * vec2(0.85, 1.4)) / 0.5, 2.0));
  bot += uGlow * 0.6 * transmit * mix(uBottom.rgb, vec3(1.0), 0.5);

  vec3 col = mix(top, bot, lower);

  // Prismatic band: each channel sees a slightly shifted interface.
  float bw = 0.042 + 0.03 * uLevel;
  float along = smoothstep(-1.25, -0.45, q.x) * smoothstep(1.25, 0.35, q.x)
              * (0.6 + 0.4 * sin(q.x * 2.1 - t * 0.8 + 1.4));
  vec3 band = vec3(0.0);
  for (int k = 0; k < 3; k++) {
    float off = (float(k) - 1.0) * 0.028 * uDisp;
    float sk = q.y - wave(q.x + off * 1.7, t, uAmp, uLevel) + off;
    float g = exp(-(sk * sk) / (bw * bw));
    band += g * spectrum(0.18 * q.x + 0.33 * float(k) + 0.05 * t);
  }
  col += band * along * (0.7 + 0.6 * uDisp);
  col += bump(s / (bw * 0.3)) * along * 0.5; // white-hot core

  // Glass thickness: edges darken, then a fresnel rim lights them.
  float fr = pow(1.0 - z, 4.0);           // thin fresnel rim
  col *= 1.0 - 0.4 * smoothstep(0.78, 1.0, d);
  col += uRim.rgb * fr * 0.55;
  float side = smoothstep(0.35, -0.75, p.x + 0.25 * p.y);
  // Hue by height, not by angle: atan() jumps at +-pi on the left rim.
  col += spectrum(p.y * 0.75 + 0.15 + 0.02 * t) * pow(1.0 - z, 3.0) * 0.75 * uDisp * side;

  // Specular highlights: a soft window at the crown, a lens glint below.
  float spec = exp(-pow(length((p - vec2(-0.3, -0.55)) * vec2(1.0, 1.8)) / 0.26, 2.0));
  col += spec * 0.12;
  float glint = exp(-pow(length((p - vec2(0.0, 0.74)) * vec2(0.85, 2.8)) / 0.4, 2.0));
  col += glint * 0.2;

  // Inner shadow under the top lip.
  col *= 1.0 - 0.3 * smoothstep(0.5, 1.0, -p.y) * smoothstep(0.3, 1.0, d);

  col = clamp(col, 0.0, 1.0);
  fragColor = vec4(col * mask, mask);
}
