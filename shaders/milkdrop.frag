// MilkDrop для Эховампа: несколько «пресетов» (туннель, калейдоскоп, спираль, жидкая плазма, лучи),
// плавно перетекающих друг в друга. Всё на видеокарте — без буферов обратной связи, поэтому дёшево.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uEnergy; // «громкость» 0..1 (плавно)
uniform float uBeat;   // удар 0..1 (быстро гаснет)
uniform float uA;      // пресет, из которого переходим
uniform float uB;      // пресет, в который переходим
uniform float uMix;    // 0..1

out vec4 fragColor;

const float PI = 3.14159265;

// косинусная палитра (Inigo Quilez) — у каждого пресета свои переливы
vec3 pal(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
  return a + b * cos(6.28318 * (c * t + d));
}

vec3 preset(float k, vec2 p, float t, float e, float beat) {
  float r = length(p);
  float a = atan(p.y, p.x);
  if (k < 0.5) {
    // 0 — туннель: кольца уходят вглубь, по кругу бежит «волна звука»
    float z = 0.35 / max(r, 0.02) + t * (0.6 + 0.8 * e);
    float rings = 0.5 + 0.5 * sin(z * 6.0 + sin(a * 3.0 + t) * 1.5);
    float stripes = 0.5 + 0.5 * sin(a * 8.0 + z * 2.0);
    vec3 col = pal(z * 0.05 + t * 0.03, vec3(0.5), vec3(0.5), vec3(1.0), vec3(0.0, 0.33, 0.67));
    col *= rings * (0.4 + 0.6 * stripes) * smoothstep(0.0, 0.25, r);
    float wave = 0.32 + 0.04 * sin(a * 7.0 + t * 5.0) * (0.4 + e) + 0.03 * beat;
    col += vec3(0.9, 1.0, 0.9) * exp(-abs(r - wave) * 90.0) * (0.6 + e);
    return col;
  } else if (k < 1.5) {
    // 1 — калейдоскоп: 8 зеркальных секторов, плазма внутри
    float n = 8.0;
    float sa = mod(a + t * 0.15, 2.0 * PI / n);
    sa = abs(sa - PI / n);
    vec2 q = vec2(cos(sa), sin(sa)) * r * (1.0 + 0.15 * beat);
    float v = sin(q.x * 10.0 + t) + sin(q.y * 12.0 - t * 1.3) + sin((q.x + q.y) * 7.0 + t * 0.7);
    vec3 col = pal(v * 0.15 + t * 0.05, vec3(0.5), vec3(0.5), vec3(1.0, 1.0, 0.5), vec3(0.8, 0.9, 0.3));
    return col * (0.55 + 0.45 * sin(v * 2.0)) * (1.0 - smoothstep(0.9, 1.4, r));
  } else if (k < 2.5) {
    // 2 — спиральный цветок: лепестки закручиваются, «дышат» под удар
    float s = sin(a * 6.0 + log(max(r, 0.001)) * 6.0 - t * 2.0);
    float petals = smoothstep(0.0, 0.9, s * 0.5 + 0.5);
    vec3 col = pal(r * 0.8 - t * 0.1, vec3(0.5), vec3(0.5), vec3(1.0), vec3(0.3, 0.2, 0.2));
    col *= petals * (0.5 + 0.5 * exp(-r * 1.5));
    col += vec3(1.0, 0.8, 0.6) * exp(-r * (8.0 - 4.0 * beat)) * 0.8;
    return col;
  } else if (k < 3.5) {
    // 3 — жидкая плазма с горизонтальной «осциллограммой»
    vec2 q = p * 2.0;
    for (int i = 0; i < 3; i++) {
      q += 0.35 * vec2(sin(q.y * 1.7 + t * 0.6 + float(i)), cos(q.x * 1.3 - t * 0.5 + float(i)));
    }
    float v = sin(q.x * 2.0) * cos(q.y * 2.0);
    vec3 col = pal(v * 0.5 + t * 0.04, vec3(0.5), vec3(0.5), vec3(2.0, 1.0, 0.0), vec3(0.5, 0.2, 0.25));
    col *= 0.45 + 0.55 * (0.5 + 0.5 * v);
    float osc = 0.08 * sin(p.x * 14.0 + t * 6.0) * (0.3 + e) + 0.03 * sin(p.x * 37.0 - t * 9.0) * e;
    col += vec3(0.7, 1.0, 0.7) * exp(-abs(p.y - osc) * 70.0) * (0.5 + e);
    return col;
  } else {
    // 4 — лучи: вращающаяся звезда из лучей, вспышки на удар
    float rays = pow(0.5 + 0.5 * cos(a * 12.0 + t * 1.5 + sin(r * 6.0 - t * 3.0)), 6.0);
    float halo = exp(-r * 2.5);
    vec3 col = pal(a / (2.0 * PI) + t * 0.05, vec3(0.5), vec3(0.5), vec3(1.0), vec3(0.0, 0.1, 0.2));
    col *= rays * halo * (1.2 + 1.5 * beat) + 0.15 * halo;
    col += vec3(1.0) * exp(-r * 18.0) * (0.6 + beat);
    return col;
  }
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 p = (frag - 0.5 * uSize) / min(uSize.x, uSize.y) * 2.0;
  // общий «зум/поворот» MilkDrop: качается и дёргается под удар
  float rot = 0.15 * sin(uTime * 0.21) + 0.05 * uBeat;
  p = mat2(cos(rot), -sin(rot), sin(rot), cos(rot)) * p;
  p *= 1.0 - 0.08 * uBeat;
  float t = uTime;
  vec3 a = preset(uA, p, t, uEnergy, uBeat);
  vec3 b = preset(uB, p, t, uEnergy, uBeat);
  vec3 col = mix(a, b, smoothstep(0.0, 1.0, uMix));
  // лёгкая «зернистость» сканлайнов, как на мониторе
  col *= 0.94 + 0.06 * sin(frag.y * 1.6);
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
