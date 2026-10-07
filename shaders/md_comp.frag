// MilkDrop, вывод на экран: цветовой ремап буфера (как frame_argb32 на ПК) — 0 чистый · 1 радужные
// контуры · 2 соляризация · 3 хром · 4 дуотон · 5 огонь · 6 лёд · 7 неон-полосы. Пресеты при смене
// перетекают: смешиваем ремап «старого» и «нового» (uRemapA → uRemapB по uMix).
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uT;
uniform float uHue;
uniform float uRemapA;
uniform float uRemapB;
uniform float uMix;
uniform sampler2D uBuf;

out vec4 fragColor;

vec3 hsv(float h, float s, float v) {
  vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
  return v * mix(vec3(1.0), k, s);
}

vec3 remap(int mode, vec3 c, float l) {
  if (mode == 1) {        // радужные контуры
    vec3 ph = vec3(0.0, 2.1, 4.2) + uT * 0.35;
    return (0.5 + 0.5 * sin(l * 11.0 + ph)) * clamp((l - 0.10) * 2.6, 0.0, 1.0) * 0.85 + c * 0.35;
  }
  if (mode == 2) {        // соляризация
    return (1.0 - abs(2.0 * c - 1.0)) * 1.25 + c * 0.25;
  }
  if (mode == 3) {        // хром
    float e = abs(sin(l * 9.0));
    return e * vec3(0.55, 0.62, 0.75) * clamp(l * 2.5 - 0.1, 0.0, 1.0) + c * 0.4;
  }
  if (mode == 4) {        // дуотон
    vec3 c1 = hsv(uHue, 0.9, 1.0), c2 = hsv(uHue + 0.42, 0.75, 1.0);
    float k = clamp(l * 1.6, 0.0, 1.0);
    return mix(c1, c2, k) * clamp(l * 2.4, 0.0, 1.0) * (0.75 + 0.25 * sin(l * 18.0 + uT)) + c * 0.3;
  }
  if (mode == 5) {        // огонь
    return vec3(clamp(l * 3.0, 0.0, 1.0), clamp(l * 3.0 - 0.9, 0.0, 1.0) * 0.85, clamp(l * 3.0 - 2.0, 0.0, 1.0) * 0.7) + c * 0.15;
  }
  if (mode == 6) {        // лёд
    float r = clamp(l * 2.6 - 1.2, 0.0, 1.0) + 0.25 * clamp(sin(l * 9.0 + uT * 0.5), 0.0, 1.0) * l;
    return vec3(r, clamp(l * 2.2 - 0.35, 0.0, 1.0), clamp(l * 2.5, 0.0, 1.0)) * 0.95 + c * 0.25;
  }
  if (mode == 7) {        // неоновые полосы
    float q = floor(l * 9.0) / 9.0;
    vec3 ph = vec3(0.0, 2.5, 4.4) + uT * 0.8;
    return (0.5 + 0.5 * sin(q * 17.0 + ph)) * clamp((l - 0.06) * 3.0, 0.0, 1.0) + c * 0.3;
  }
  return sqrt(c) * 0.35 + c * 0.7;  // 0 — чистый
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 c = min(texture(uBuf, uv).rgb, vec3(1.0));
  float l = (c.r + c.g + c.b) / 3.0;
  vec3 a = remap(int(uRemapA + 0.5), c, l);
  vec3 b = remap(int(uRemapB + 0.5), c, l);
  fragColor = vec4(clamp(mix(a, b, uMix), 0.0, 1.0), 1.0);
}
