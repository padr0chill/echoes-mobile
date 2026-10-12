// «Моя волна» — туманность, как в ECHOES на ПК (ya_wave.py → NebulaField): десять светящихся пятен в цветах
// обложки медленно кружат внутри одного облака с «колышущимся» краем, по ним текут тонкие прожилки света,
// на ударах расходятся кольца. Положения пятен считает Dart (каждый кадр), здесь — только пиксели.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uCenter;    // центр облака, px
uniform float uR;        // радиус облака, px
uniform float uT;        // время туманности (быстрее, когда играет)
uniform float uEnergy;   // 0..1 — громкость/«дыхание»
uniform float uKick;     // 0..1 — вспышка удара
uniform vec3 uFil;       // цвет прожилок
uniform vec3 uRingCol;   // цвет колец
uniform vec4 uBlob[10];  // x, y (доли радиуса), 1/r², сила
uniform vec4 uBlobCol[10]; // цвет пятна (rgb)
uniform vec4 uRings[3];  // (радиус, яркость) × 2

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy;
  float u = (p.x - uCenter.x) / uR;
  float v = (p.y - uCenter.y) / uR;
  float t = uT * 0.55;

  // «течение»: две ступени завихрения координат
  float w1x = u + 0.30 * sin(v * 1.9 + t * 0.7) + 0.15 * sin(v * 3.7 - t * 0.5 + u * 1.3);
  float w1y = v + 0.30 * sin(u * 1.7 - t * 0.6) + 0.15 * sin(u * 3.3 + t * 0.45 - v * 1.1);
  float w2x = w1x + 0.10 * sin(w1y * 5.1 + t * 0.9);
  float w2y = w1y + 0.10 * sin(w1x * 4.7 - t * 0.8);
  float qx = u + (w2x - u) * 0.55;
  float qy = v + (w2y - v) * 0.55;

  vec3 acc = vec3(0.0);
  for (int i = 0; i < 10; i++) {
    vec4 b = uBlob[i];
    float dx = qx - b.x, dy = qy - b.y;
    acc += exp(-(dx * dx + dy * dy) * b.z) * b.w * uBlobCol[i].rgb;
  }
  float lum = max(acc.r, max(acc.g, acc.b));

  // прожилки света — тонкие линии уровня плавного поля, только там, где светло
  float f = sin((sin(w1x * 2.3 + sin(w1y * 1.7 + t * 0.3)) + sin(w1y * 2.1 - sin(w1x * 1.9 - t * 0.25))) * 2.6);
  float fl = (exp(-(f / 0.085) * (f / 0.085)) * 0.85 + exp(-(f / 0.3) * (f / 0.3)) * 0.18) *
             clamp(lum * 1.6, 0.0, 1.0) * (0.32 + 0.25 * uEnergy);
  acc += fl * (uFil * 0.4 + 0.6 * clamp(acc / max(lum, 0.05), 0.0, 1.0));

  // кольца от ударов
  float r = sqrt(u * u + v * v);
  for (int i = 0; i < 3; i++) {
    vec4 rg = uRings[i];
    float d1 = (r - rg.x) / 0.14, d2 = (r - rg.z) / 0.14;
    acc += (exp(-d1 * d1) * rg.y + exp(-d2 * d2) * rg.w) * uRingCol;
  }

  // край облака — мягкий и волнистый
  float ang = atan(v, u);
  float rs = (0.90 + 0.06 * uEnergy + 0.07 * uKick) *
             (1.0 + 0.11 * (0.55 * sin(3.0 * ang + t * 0.3) + 0.35 * sin(5.0 * ang - t * 0.42) +
                            0.25 * sin(2.0 * ang + t * 0.21 + 1.7)));
  float e2 = (r / rs) * (r / rs);
  vec3 img = (1.0 - exp(-acc * 1.25 * 1.15)) * exp(-e2 * e2 * 1.1);
  fragColor = vec4(clamp(img, 0.0, 1.0), 1.0);
}
