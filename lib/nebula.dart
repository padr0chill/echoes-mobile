import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// «Моя волна» — туманность как в ECHOES на ПК (ya_wave.py → NebulaField): здесь движение пятен, удары и
/// кольца, а пиксели считает шейдер shaders/nebula.frag.
///
/// iOS не отдаёт приложению сам звук, поэтому удары — синтетические: ровный ритм ~120 BPM с акцентами,
/// пока играет музыка.
class Nebula {
  /// x, y (доли радиуса), r, цвет (0..3; 0.5 — смесь 0 и 1), сила, орбита, fx, fy, фаза — как на ПК.
  static const layout = <List<double>>[
    [0.00, -0.02, 0.64, 0, 1.10, 0.08, 0.31, 0.27, 0.0],
    [0.18, 0.08, 0.42, 0.5, 0.80, 0.22, 0.23, 0.35, 1.3],
    [-0.50, 0.10, 0.52, 1, 0.70, 0.16, 0.19, 0.24, 2.1],
    [0.52, -0.12, 0.48, 1, 0.62, 0.18, 0.27, 0.21, 3.7],
    [-0.70, -0.46, 0.55, 2, 0.80, 0.14, 0.17, 0.29, 0.6],
    [0.84, 0.22, 0.50, 2, 0.65, 0.15, 0.21, 0.18, 4.4],
    [0.08, 0.86, 0.62, 3, 0.85, 0.13, 0.25, 0.20, 5.1],
    [-0.80, 0.62, 0.45, 3, 0.65, 0.17, 0.29, 0.23, 2.8],
    [0.70, -0.78, 0.45, 3, 0.55, 0.15, 0.22, 0.31, 1.9],
    [0.20, 0.06, 0.24, 0, 0.55, 0.20, 0.41, 0.37, 3.3],
  ];

  /// Четыре цвета: ядро, середина, край 1, край 2 — те же схемы, что на ПК.
  static const schemes = <String, List<Color>>{
    'my': [Color(0xFFFFD21A), Color(0xFFFF9A1A), Color(0xFFE2179C), Color(0xFF43E04A)],
    'energy': [Color(0xFFC21BFF), Color(0xFFFF2A9E), Color(0xFFFF4A1A), Color(0xFF36E07A)],
    'calm': [Color(0xFF7FE8FF), Color(0xFF2A9BFF), Color(0xFF4A2CFF), Color(0xFF20E0C0)],
    'happy': [Color(0xFFFFF23A), Color(0xFF7DFF3A), Color(0xFFFF7A1A), Color(0xFF20D0FF)],
    'sad': [Color(0xFF2EE6B0), Color(0xFF16C8C0), Color(0xFF1A3CFF), Color(0xFF9A1FD6)],
    'fresh': [Color(0xFF3CFF3C), Color(0xFF1FD86A), Color(0xFF1A6CFF), Color(0xFF0FD6C0)],
    'fav': [Color(0xFFFF4A8A), Color(0xFFFF8A3A), Color(0xFFB01AFF), Color(0xFFFFC0DC)],
    'night': [Color(0xFFB9A8FF), Color(0xFF6A4CFF), Color(0xFF2A1A8F), Color(0xFF20B0FF)],
  };

  /// Настроения волны телефона → схемы ПК.
  static List<Color> forMood(String? mood) => schemes[switch (mood) {
        'Энергичное' => 'energy',
        'Спокойное' => 'calm',
        'Грустное' => 'sad',
        'Тренировка' => 'happy',
        'Для сна' => 'night',
        'Русский рэп' => 'fav',
        _ => 'my',
      }]!;

  /// Схема из главного цвета обложки (как scheme_from_hue на ПК).
  static List<Color> fromColor(Color c) {
    final hsv = HSVColor.fromColor(c);
    final h = hsv.hue / 360, s = math.max(0.75, hsv.saturation);
    Color x(double dh, double ss, double vv) =>
        HSVColor.fromAHSV(1, ((h + dh) % 1.0) * 360, ss.clamp(0.0, 1.0), vv).toColor();
    return [x(0, 0.72 * s + 0.1, 1.0), x(0.05, 0.92 * s, 0.95), x(0.20, 0.88 * s, 0.92), x(-0.24 + 1, 0.85 * s, 0.88)];
  }

  double tt = 0, kick = 0, energy = 0;
  final rings = <List<double>>[]; // [радиус, яркость]
  final _rnd = math.Random();
  double _nextBeat = 0, _beatClock = 0;
  int _beatN = 0;

  void hit(double strength) {
    kick = math.min(1.0, kick + 0.7 * strength);
    rings.add([0.15, 0.30 * strength]);
    if (rings.length > 6) rings.removeAt(0);
  }

  /// Шаг анимации: playing — 0..1 (плавно), dt — секунды.
  void advance(double playing, double dt) {
    // синтетический ритм: удар каждые ~0,5 с, сильная доля — каждая четвёртая
    final target = playing * (0.32 + 0.12 * math.sin(_beatClock * 1.3));
    if (playing > 0.5) {
      _beatClock += dt;
      if (_beatClock >= _nextBeat) {
        _beatN++;
        final strong = _beatN % 4 == 1;
        hit(strong ? 0.75 + 0.25 * _rnd.nextDouble() : 0.25 + 0.2 * _rnd.nextDouble());
        _nextBeat = _beatClock + 0.48 + _rnd.nextDouble() * 0.06;
      }
    }
    energy += (target - energy) * math.min(1.0, dt * 3);
    tt += dt * (1.0 + 1.6 * energy + 1.2 * kick);
    kick *= math.exp(-dt * 2.8);
    for (final r in rings) {
      r[0] += dt * (0.9 + 0.5 * energy);
      r[1] *= math.exp(-dt * 1.3);
    }
    rings.removeWhere((r) => r[1] <= 0.01 || r[0] >= 2.6);
  }

  /// Записать параметры кадра в шейдер (порядок — как объявлены uniform в nebula.frag).
  void apply(ui.FragmentShader shader, Size size, List<Color> cols) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h * 0.42;
    final r = math.max(120.0, math.min(w * 0.56, h * 0.34));
    var i = 0;
    void f(double v) => shader.setFloat(i++, v);
    f(w);
    f(h);
    f(cx);
    f(cy);
    f(r);
    f(tt);
    f(energy);
    f(kick);
    final c0 = cols[0];
    // прожилки — светлее ядра, кольца — чуть темнее
    f((c0.r * 0.5 + 0.55).clamp(0, 1));
    f((c0.g * 0.5 + 0.55).clamp(0, 1));
    f((c0.b * 0.5 + 0.55).clamp(0, 1));
    f((c0.r * 0.6 + 0.25).clamp(0, 1));
    f((c0.g * 0.6 + 0.25).clamp(0, 1));
    f((c0.b * 0.6 + 0.25).clamp(0, 1));
    // пятна: медленное вращение всего облака + своя орбита у каждого; «дыхание» от ритма
    final rot = tt * 0.035, cr = math.cos(rot), sr = math.sin(rot);
    final breath = 1.0 + 0.10 * energy + 0.16 * kick + 0.03 * math.sin(tt * 0.9);
    final colors = <Color>[];
    for (final b in layout) {
      var bx = (b[0] + b[5] * math.sin(tt * b[6] + b[8])) * 0.74;
      var by = (b[1] + b[5] * math.cos(tt * b[7] + b[8] * 1.3)) * 0.74;
      final rx = bx * cr - by * sr, ry = bx * sr + by * cr;
      bx = rx;
      by = ry;
      final rr = b[2] * breath * 0.92;
      f(bx);
      f(by);
      f(1 / (rr * rr));
      f(b[4] * (1.0 + 0.25 * kick));
      colors.add(b[3] == 0.5 ? Color.lerp(cols[0], cols[1], 0.5)! : cols[b[3].toInt()]);
    }
    for (final c in colors) {
      f(c.r);
      f(c.g);
      f(c.b);
      f(1);
    }
    // три vec4 = шесть колец (радиус, яркость)
    for (var k = 0; k < 6; k++) {
      f(k < rings.length ? rings[k][0] : 9);
      f(k < rings.length ? rings[k][1] : 0);
    }
  }
}
