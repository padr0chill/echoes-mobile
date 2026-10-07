import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'models.dart';
import 'widgets.dart';

final _cache = <String, Color?>{};

/// Главный цвет обложки (как Яндекс Музыка красит волну под трек): обложка 24×24 → самый «весомый»
/// оттенок по насыщенности и яркости. null — обложка не загрузилась или она серая.
Future<Color?> coverColor(Track t) async {
  if (_cache.containsKey(t.id)) return _cache[t.id];
  final ImageProvider src = Cover.debugImage?.call(t) ?? NetworkImage(t.art ?? t.thumb);
  final c = await _dominant(ResizeImage(src, width: 24, height: 24))
      .timeout(const Duration(seconds: 8), onTimeout: () => null);
  if (_cache.length > 300) _cache.clear();
  return _cache[t.id] = c;
}

Future<Color?> _dominant(ImageProvider p) async {
  final done = Completer<ui.Image?>();
  final stream = p.resolve(ImageConfiguration.empty);
  late final ImageStreamListener l;
  l = ImageStreamListener((info, _) {
    if (!done.isCompleted) done.complete(info.image.clone());
    stream.removeListener(l);
  }, onError: (_, __) {
    if (!done.isCompleted) done.complete(null);
    stream.removeListener(l);
  });
  stream.addListener(l);
  final img = await done.future;
  if (img == null) return null;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  if (data == null) return null;
  // гистограмма оттенков по 24 корзинам, вес = насыщенность × яркость
  final w = List<double>.filled(24, 0);
  final sum = List.generate(24, (_) => [0.0, 0.0, 0.0]);
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    final c = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    final h = HSVColor.fromColor(c);
    final k = h.saturation * h.value;
    if (k < 0.12) continue;
    final b = (h.hue / 15).floor() % 24;
    w[b] += k;
    sum[b][0] += c.r * k;
    sum[b][1] += c.g * k;
    sum[b][2] += c.b * k;
  }
  var best = -1;
  for (var b = 0; b < 24; b++) {
    if (best < 0 || w[b] > w[best]) best = b;
  }
  if (best < 0 || w[best] < 1.5) return null; // почти чёрно-белая обложка
  return Color.from(alpha: 1, red: sum[best][0] / w[best], green: sum[best][1] / w[best], blue: sum[best][2] / w[best]);
}

/// Палитра пламени из одного цвета: светлое ядро → цвет → глубже → почти тёмный край.
List<Color> paletteFromColor(Color c) {
  final h = HSLColor.fromColor(c);
  final s = h.saturation.clamp(0.7, 1.0);
  Color x(double dh, double l) => HSLColor.fromAHSL(1, (h.hue + dh) % 360, s, l).toColor();
  return [x(-6, 0.70), x(0, 0.55), x(10, 0.42), x(22, 0.26)];
}
