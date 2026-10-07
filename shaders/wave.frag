// «Моя волна»: облако цвета обложки + светящиеся «каустики» (прожилки света, как на дне бассейна),
// как у волны Яндекс Музыки. Считается на видеокарте — дёшево и плавно даже на 120 Гц.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uEnergy; // 0..1 — играет ли музыка (плавно)
uniform vec3 uC0;      // светлое ядро
uniform vec3 uC1;      // основной цвет
uniform vec3 uC2;      // глубже
uniform vec3 uC3;      // тёмный край

out vec4 fragColor;

// плавное «закрученное» поле; его нулевые линии — извилистые прожилки света, как у Яндекса
float field(vec2 p, float t) {
  vec2 q = p + vec2(0.55 * sin(p.y * 1.7 + t * 0.6) + 0.30 * sin(p.y * 3.1 - t * 0.4),
                    0.55 * sin(p.x * 1.9 - t * 0.5) + 0.30 * sin(p.x * 2.7 + t * 0.35));
  return sin(q.x * 1.6 + sin(q.y * 1.3 + t * 0.3)) + sin(q.y * 1.4 - sin(q.x * 1.1 - t * 0.25));
}

// яркость прожилок: тонкая середина + широкое мягкое свечение; две сетки разного масштаба
float veins(vec2 p, float t) {
  // линии на нескольких уровнях поля (sin(k·f) = 0), а не только на нуле — прожилок 4–6 на экран
  float f = sin(field(p, t) * 2.4);
  float g = sin(field(p * 1.25 + vec2(5.0, -3.0), t * 1.2 + 7.0) * 2.0);
  const float w = 0.16;
  float core = exp(-(f / w) * (f / w)) + 0.7 * exp(-(g / w) * (g / w));
  float glow = 0.35 * exp(-(f / (w * 4.0)) * (f / (w * 4.0))) + 0.25 * exp(-(g / (w * 4.0)) * (g / (w * 4.0)));
  return core * 0.6 + glow;
}
void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float aspect = uSize.x / uSize.y;
  float t = uTime;

  // облако: бесформенное пятно вокруг точки чуть выше центра, края «колышутся»
  vec2 q = vec2((uv.x - 0.5) * aspect, uv.y - 0.42);
  float scale = min(aspect, 0.75);
  q /= scale;
  q += 0.06 * vec2(sin(t * 0.37), cos(t * 0.29));
  float r = length(q);
  float a = atan(q.y, q.x);
  float wob = 1.0 + 0.14 * sin(3.0 * a + t * 0.9) + 0.09 * sin(5.0 * a - t * 1.2) + 0.05 * sin(2.0 * a + t * 0.6);
  float beat = 1.0 + 0.04 * uEnergy * sin(t * 6.0);
  float cloud = 1.0 - smoothstep(0.05, 0.95, r / (0.78 * wob * beat));
  float core = 1.0 - smoothstep(0.0, 0.42, r / (wob * beat));

  vec3 col = uC3 * (0.35 + 0.65 * smoothstep(0.0, 0.25, cloud));
  col = mix(col, uC2, smoothstep(0.10, 0.50, cloud));
  col = mix(col, uC1, smoothstep(0.40, 0.85, cloud));
  col = mix(col, uC0, core * 0.85);

  // прожилки: мягкий свет цвета ядра, вплетён в облако (не белые линии поверх); текут медленно,
  // под музыку — быстрее и ярче
  vec2 p = vec2(uv.x * aspect, uv.y) * 2.2;
  float v = veins(p, t * 0.45);
  vec3 light = mix(uC0, vec3(1.0), 0.45);
  float amt = (0.38 + 0.17 * uEnergy) * (0.25 + 0.75 * smoothstep(0.0, 0.5, cloud));
  col += light * v * amt;
  col = col / (1.0 + 0.25 * max(col - 1.0, 0.0)); // мягкий потолок вместо пересвета
  // мягкое затемнение к краям экрана
  float vig = smoothstep(1.25, 0.35, length((uv - vec2(0.5, 0.45)) * vec2(aspect, 1.0)));
  col *= 0.55 + 0.45 * vig;
  fragColor = vec4(col, 1.0);
}
