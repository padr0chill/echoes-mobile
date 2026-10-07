// MilkDrop, шаг обратной связи (как milkdrop_core.step на ПК): прошлый кадр через «сетку движения» —
// зум (зависит от радиуса), поворот, анизотропия, варп (5 режимов), дрейф вокруг смещённого блуждающего
// центра; затем затухание и вспышка. Волны дорисовываются поверх уже на холсте.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;   // размер буфера
uniform float uLz;    // log(zoom) · f
uniform float uZexp;
uniform float uRot;   // поворот за кадр
uniform float uAn;    // aniso^f
uniform float uWa;    // сила варпа
uniform float uWs;    // частота варпа
uniform float uWt;    // время течения
uniform float uWmode; // 0 синус · 1 вихрь · 2 поток · 3 рябь · 4 турбулентность
uniform vec2 uC;      // центр движения
uniform vec2 uD;      // дрейф за кадр
uniform float uDecay; // decay^f
uniform float uSub;   // вычитание за кадр (хвосты гаснут до чёрного)
uniform float uFlash;
uniform sampler2D uPrev;

out vec4 fragColor;

void main() {
  vec2 uv0 = FlutterFragCoord().xy / uSize;
  float A = uSize.x / uSize.y;
  float X = (uv0.x * 2.0 - 1.0) * A;
  float Y = uv0.y * 2.0 - 1.0;
  float Xc = X - uC.x, Yc = Y - uC.y;
  float R = sqrt(Xc * Xc + Yc * Yc);
  float scale = exp(R * (-uLz * uZexp) + (-uLz + uLz * uZexp * 0.6));
  float c = cos(uRot), s = sin(uRot);
  float u = (Xc * c - Yc * s) * scale * uAn;
  float v = (Xc * s + Yc * c) * scale / uAn;
  float wa = uWa, ws = uWs, wt = uWt;
  int wm = int(uWmode + 0.5);
  if (wm == 1) {          // вихрь вокруг центра
    float ang = (wa * 6.0) * exp(-R * R * 1.6);
    float ca = cos(ang), sa = sin(ang);
    float u2 = u * ca - v * sa;
    v = u * sa + v * ca;
    u = u2 + wa * 0.4 * sin(Yc * ws + wt);
  } else if (wm == 2) {   // диагональный поток
    u += wa * sin(Y * ws + X * 0.6 * ws + wt * 1.1);
    v += wa * 0.7 * cos(X * ws * 1.3 - wt * 0.6) + wa * 0.15;
  } else if (wm == 3) {   // рябь от центра
    float rip = wa * 1.4 * sin(R * ws * 3.0 - wt * 3.0) / (R + 0.15);
    u += Xc * rip;
    v += Yc * rip;
  } else if (wm == 4) {   // турбулентность (две октавы)
    u += wa * (sin(Y * ws * 1.17 + wt * 1.3 + 0.7) + 0.5 * sin(X * ws * 2.71 - wt * 0.9 + Y * 1.3));
    v += wa * (cos(X * ws * 0.93 - wt * 1.07) + 0.5 * cos(Y * ws * 2.33 + wt * 1.6 + X * 0.8));
  } else {                // синус (несимметричные фазы)
    u += wa * sin(Y * ws + wt * 1.13 + 0.9);
    v += wa * cos(X * ws * 0.9 + wt * 0.87 + 0.3);
  }
  u += uC.x + uD.x;
  v += uC.y + uD.y;
  vec2 suv = clamp(vec2(u / A * 0.5 + 0.5, v * 0.5 + 0.5), vec2(0.001), vec2(0.999));
  vec3 col = texture(uPrev, suv).rgb;
  col = max(col * uDecay - uSub, 0.0) * (1.0 + uFlash * 0.5);
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
