// Проверка формул эквалайзера (те же, что в packages/echoes_eq/ios/Classes/EchoesEqPlugin.m): полоса
// поднимает/опускает ровно на заданные дБ на своей частоте и почти не трогает далёкие частоты.
import 'dart:math' as math;

import 'package:echoes_mobile/screens/equalizer_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Коэффициенты peaking EQ (RBJ), Q = 1.41 — как в нативном коде.
List<double> coef(double f0, double gainDb, double fs) {
  final a = math.pow(10, gainDb / 40).toDouble();
  final w0 = 2 * math.pi * f0 / fs;
  final alpha = math.sin(w0) / (2 * 1.41);
  final cw = math.cos(w0);
  final a0 = 1 + alpha / a;
  return [(1 + alpha * a) / a0, -2 * cw / a0, (1 - alpha * a) / a0, -2 * cw / a0, (1 - alpha / a) / a0];
}

/// Усиление фильтра на частоте f, дБ.
double responseDb(List<double> c, double f, double fs) {
  final w = 2 * math.pi * f / fs;
  // H(e^jw) = (b0 + b1 e^-jw + b2 e^-2jw) / (1 + a1 e^-jw + a2 e^-2jw)
  double re(double b0, double b1, double b2) => b0 + b1 * math.cos(w) + b2 * math.cos(2 * w);
  double im(double b1, double b2) => -b1 * math.sin(w) - b2 * math.sin(2 * w);
  final nr = re(c[0], c[1], c[2]), ni = im(c[1], c[2]);
  final dr = re(1, c[3], c[4]), di = im(c[3], c[4]);
  return 20 * math.log((math.sqrt(nr * nr + ni * ni) / math.sqrt(dr * dr + di * di))) / math.ln10;
}

void main() {
  const fs = 44100.0;
  test('полоса даёт ровно свои дБ на своей частоте', () {
    for (final f in [32.0, 125.0, 1000.0, 8000.0, 16000.0]) {
      for (final g in [-12.0, -6.0, 3.0, 12.0]) {
        expect(responseDb(coef(f, g, fs), f, fs), closeTo(g, 0.05), reason: '$f Гц, $g дБ');
      }
    }
  });

  test('далёкие частоты почти не трогает (полоса 1 кГц, +12 дБ)', () {
    final c = coef(1000, 12, fs);
    expect(responseDb(c, 60, fs).abs(), lessThan(0.6));
    expect(responseDb(c, 15000, fs).abs(), lessThan(0.6));
  });

  test('пресеты: 10 полос в пределах ±12 дБ, предусиление гасит подъём', () {
    for (final e in eqPresets.entries) {
      expect(e.value.length, 10, reason: e.key);
      expect(e.value.every((v) => v.abs() <= 12), isTrue, reason: e.key);
      expect(presetPreamp(e.value) <= 0, isTrue, reason: e.key);
    }
    expect(presetPreamp(eqPresets['Бас+']!), -4);
    expect(presetPreamp(eqPresets['Плоский']!), 0);
  });
}
