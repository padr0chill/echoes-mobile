import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// MilkDrop как на ПК (milkdrop_core.py), перенесённый на видеокарту телефона:
///  1. буфер обратной связи — прошлый кадр через «сетку движения» (shaders/md_warp.frag);
///  2. затухание и вспышки на удар;
///  3. волна рисуется в буфер (15 видов, как на ПК) — она «источник света», дальше её тянет и плавит;
///  4. «звук» двигает картинку: bass / mid / treb относительно среднего (≈1 — обычно, 1.6 — удар);
///  5. пресеты (39 ручных + 96 сгенерированных = 135) плавно перетекают; смена: авто / на удар / замок;
///  6. цветовой ремап на выходе (shaders/md_comp.frag).
/// Звука плеер iOS не отдаёт — bass/mid/treb, спектр и волну даёт ритм-генератор, пока играет музыка.

typedef MdParams = Map<String, double>;

const _defaults = <String, double>{
  'zoom': 1.02, 'rot': 0.0, 'warp': 0.4, 'wscale': 2.0, 'wspeed': 1.0, 'wmode': 0, //
  'decay': 0.968, 'zexp': 0.5, 'dx': 0.0, 'dy': 0.0, 'cx': 0.0, 'cy': 0.0, 'orbit': 0.25, //
  'ospeed': 0.25, 'aniso': 1.0, 'wave': 0, 'wsize': 0.30, 'wx': 0.0, 'wy': 0.0, //
  'hue_speed': 0.08, 'hue0': 0.0, 'remap': 1,
};

class MdPreset {
  final String name;
  final MdParams p;
  MdPreset(this.name, Map<String, double> kw) : p = {..._defaults, ...kw};
}

MdPreset _p(String name, Map<String, double> kw) => MdPreset(name, kw);

/// Ручные пресеты — те же, что в ECHOES на ПК.
final _manual = <MdPreset>[
  // ── смещённые туннели и вихри ──
  _p('off-axis tunnel', {
    'zoom': 1.032,
    'rot': 0.008,
    'warp': 0.5,
    'wscale': 2.2,
    'wspeed': 0.9,
    'cx': 0.45,
    'cy': -0.25,
    'orbit': 0.2,
    'wave': 0,
    'wsize': 0.30,
    'wx': 0.5,
    'wy': -0.2,
    'remap': 1,
    'zexp': 0.6
  }),
  _p('drain to the corner', {
    'zoom': 1.045,
    'rot': 0.02,
    'warp': 0.3,
    'wmode': 1,
    'cx': -0.9,
    'cy': 0.55,
    'orbit': 0.12,
    'wave': 5,
    'wsize': 0.45,
    'wx': -0.6,
    'wy': 0.3,
    'remap': 4,
    'hue0': 0.75,
    'decay': 0.972
  }),
  _p('lopsided vortex', {
    'zoom': 1.018,
    'rot': 0.03,
    'warp': 0.9,
    'wmode': 1,
    'wscale': 1.6,
    'cx': 0.3,
    'cy': 0.35,
    'orbit': 0.35,
    'wave': 2,
    'wsize': 0.40,
    'wx': 0.35,
    'wy': 0.3,
    'remap': 2
  }),
  _p('comet wake', {
    'zoom': 1.012,
    'rot': -0.006,
    'warp': 0.55,
    'wmode': 2,
    'dx': 0.004,
    'dy': -0.003,
    'cx': -0.5,
    'wave': 9,
    'wsize': 0.45,
    'remap': 1,
    'decay': 0.975
  }),
  _p('orbit garden', {
    'zoom': 1.022,
    'rot': 0.012,
    'warp': 0.35,
    'wmode': 4,
    'cx': 0.6,
    'cy': -0.3,
    'orbit': 0.3,
    'wave': 8,
    'wsize': 0.5,
    'wx': 0.25,
    'wy': -0.1,
    'remap': 6,
    'hue_speed': 0.05
  }),
  _p('sideways spectrum', {
    'zoom': 1.008,
    'rot': 0.0,
    'warp': 0.7,
    'wmode': 2,
    'dx': 0.012,
    'cx': -1.2,
    'orbit': 0.1,
    'aniso': 1.04,
    'wave': 7,
    'wsize': 0.6,
    'remap': 7
  }),
  _p('spiral off-center', {
    'zoom': 1.028,
    'rot': -0.025,
    'warp': 0.25,
    'wmode': 0,
    'cx': -0.35,
    'cy': 0.4,
    'orbit': 0.25,
    'wave': 5,
    'wsize': 0.35,
    'wx': -0.3,
    'wy': 0.35,
    'remap': 1,
    'hue_speed': 0.14
  }),
  _p('ember drift', {
    'zoom': 1.006,
    'rot': 0.004,
    'warp': 0.6,
    'wmode': 4,
    'dy': -0.010,
    'cx': 0.2,
    'cy': 0.8,
    'orbit': 0.3,
    'wave': 6,
    'wsize': 0.6,
    'wx': 0.1,
    'wy': 0.6,
    'remap': 5,
    'decay': 0.976,
    'hue0': 0.02,
    'hue_speed': 0.02
  }),
  _p('frost crawl', {
    'zoom': 1.004,
    'rot': -0.003,
    'warp': 0.8,
    'wmode': 3,
    'wscale': 2.6,
    'cx': -0.7,
    'cy': -0.5,
    'orbit': 0.2,
    'wave': 1,
    'wsize': 0.30,
    'wy': -0.35,
    'remap': 6,
    'decay': 0.974
  }),
  _p('acid scope askew', {
    'zoom': 0.994,
    'rot': 0.018,
    'warp': 0.8,
    'wscale': 1.6,
    'wspeed': 0.7,
    'cx': 0.4,
    'cy': 0.2,
    'orbit': 0.3,
    'wave': 2,
    'wsize': 0.42,
    'wx': 0.4,
    'wy': 0.25,
    'remap': 2,
    'decay': 0.958
  }),
  _p('chrome river bend', {
    'zoom': 1.010,
    'warp': 1.1,
    'wscale': 2.6,
    'wspeed': 1.6,
    'wmode': 2,
    'dx': 0.006,
    'dy': -0.002,
    'cx': -0.3,
    'wave': 1,
    'wsize': 0.34,
    'wy': 0.3,
    'remap': 3,
    'decay': 0.972
  }),
  _p('feathers leaning', {
    'zoom': 1.024,
    'rot': -0.004,
    'warp': 0.65,
    'wscale': 1.3,
    'wspeed': 0.5,
    'zexp': 1.5,
    'dy': 0.003,
    'cx': 0.5,
    'cy': 0.3,
    'wave': 3,
    'wsize': 0.30,
    'wx': 0.3,
    'remap': 1,
    'decay': 0.980
  }),
  _p('plasma drain east', {
    'zoom': 0.975,
    'rot': 0.030,
    'warp': 0.45,
    'cx': 0.8,
    'cy': -0.1,
    'zexp': -0.4,
    'wave': 2,
    'wsize': 0.38,
    'wx': 0.6,
    'remap': 2,
    'decay': 0.960
  }),
  _p('neon spiral slip', {
    'zoom': 1.035,
    'rot': 0.035,
    'warp': 0.15,
    'wscale': 3.5,
    'wspeed': 2.0,
    'cx': -0.4,
    'cy': -0.3,
    'orbit': 0.3,
    'wave': 4,
    'wsize': 0.24,
    'wx': -0.45,
    'wy': -0.3,
    'remap': 0,
    'hue_speed': 0.20
  }),
  _p('heart of a red giant', {
    'zoom': 1.050,
    'rot': 0.004,
    'warp': 0.4,
    'wscale': 2.8,
    'cx': 0.55,
    'cy': 0.45,
    'orbit': 0.15,
    'wave': 0,
    'wsize': 0.22,
    'wx': 0.5,
    'wy': 0.4,
    'remap': 5,
    'hue0': 0.0,
    'hue_speed': 0.03
  }),
  _p('ripple pond', {
    'zoom': 1.004,
    'rot': 0.002,
    'warp': 0.9,
    'wmode': 3,
    'wscale': 3.0,
    'wspeed': 1.4,
    'cx': -0.5,
    'cy': 0.25,
    'orbit': 0.4,
    'wave': 8,
    'wsize': 0.35,
    'wx': -0.4,
    'wy': 0.2,
    'remap': 4,
    'hue0': 0.55
  }),
  _p('tilted horizon', {
    'zoom': 1.015,
    'rot': 0.006,
    'warp': 0.5,
    'wmode': 2,
    'aniso': 1.03,
    'cy': -0.6,
    'wave': 1,
    'wsize': 0.45,
    'wy': -0.5,
    'remap': 7,
    'hue_speed': 0.11
  }),
  _p('magnet sparks', {
    'zoom': 1.03,
    'rot': -0.015,
    'warp': 0.3,
    'wmode': 1,
    'cx': 0.7,
    'cy': -0.5,
    'orbit': 0.2,
    'wave': 6,
    'wsize': 0.5,
    'wx': 0.5,
    'wy': -0.4,
    'remap': 1,
    'decay': 0.966
  }),
  _p('violet undertow', {
    'zoom': 0.985,
    'rot': -0.01,
    'warp': 0.7,
    'wmode': 4,
    'cx': -0.6,
    'cy': 0.6,
    'orbit': 0.25,
    'wave': 5,
    'wsize': 0.4,
    'wx': -0.4,
    'wy': 0.5,
    'remap': 4,
    'hue0': 0.78,
    'hue_speed': 0.03
  }),
  _p('lazy lissajous', {
    'zoom': 1.01,
    'rot': 0.009,
    'warp': 0.4,
    'wmode': 0,
    'cx': 0.25,
    'cy': -0.45,
    'orbit': 0.45,
    'ospeed': 0.15,
    'wave': 9,
    'wsize': 0.55,
    'remap': 6,
    'decay': 0.978
  }),
  _p('bent oscilloscope', {
    'zoom': 1.02,
    'rot': -0.02,
    'warp': 1.2,
    'wmode': 3,
    'wscale': 1.4,
    'cx': -0.2,
    'cy': 0.5,
    'wave': 2,
    'wsize': 0.5,
    'wx': -0.3,
    'wy': 0.4,
    'remap': 3
  }),
  _p('hot pink current', {
    'zoom': 1.012,
    'warp': 0.75,
    'wmode': 2,
    'dx': -0.008,
    'dy': 0.004,
    'cx': 0.9,
    'wave': 3,
    'wsize': 0.32,
    'wy': 0.15,
    'remap': 4,
    'hue0': 0.9,
    'hue_speed': 0.02,
    'decay': 0.97
  }),
  _p('cyclone eye', {
    'zoom': 1.04,
    'rot': 0.045,
    'warp': 0.6,
    'wmode': 1,
    'wscale': 2.0,
    'cx': -0.55,
    'cy': -0.35,
    'orbit': 0.18,
    'wave': 4,
    'wsize': 0.28,
    'wx': -0.55,
    'wy': -0.35,
    'remap': 1,
    'hue_speed': 0.16
  }),
  _p('liquid stairs', {
    'zoom': 1.008,
    'rot': 0.0,
    'warp': 0.9,
    'wmode': 4,
    'wscale': 3.4,
    'aniso': 0.97,
    'cx': 0.4,
    'cy': 0.6,
    'wave': 7,
    'wsize': 0.5,
    'remap': 7,
    'decay': 0.97
  }),
  _p('smoke signal', {
    'zoom': 1.0,
    'rot': 0.003,
    'warp': 0.5,
    'wmode': 4,
    'dy': -0.012,
    'cx': -0.6,
    'cy': 0.7,
    'orbit': 0.2,
    'wave': 1,
    'wsize': 0.25,
    'wx': -0.5,
    'wy': 0.7,
    'remap': 3,
    'decay': 0.982
  }),
  _p('gravity well', {
    'zoom': 1.06,
    'rot': -0.008,
    'warp': 0.2,
    'wmode': 3,
    'zexp': 1.4,
    'cx': 0.75,
    'cy': 0.5,
    'orbit': 0.1,
    'wave': 6,
    'wsize': 0.7,
    'remap': 5,
    'decay': 0.962
  }),
  // ── глобальные: картинка на весь кадр ──
  _p('[full] wave curtains', {
    'zoom': 1.006,
    'rot': 0.0,
    'warp': 0.6,
    'wmode': 2,
    'dy': -0.004,
    'orbit': 0.3,
    'wave': 10,
    'wsize': 0.18,
    'remap': 1,
    'decay': 0.962,
    'hue_speed': 0.07
  }),
  _p('[full] spectrum floor', {
    'zoom': 1.012,
    'rot': 0.0,
    'warp': 0.4,
    'wmode': 4,
    'dy': -0.014,
    'cx': 0.3,
    'cy': 1.0,
    'orbit': 0.2,
    'aniso': 1.02,
    'wave': 11,
    'wsize': 0.9,
    'remap': 7,
    'decay': 0.968
  }),
  _p('[full] plasma sea', {
    'zoom': 1.004,
    'rot': 0.002,
    'warp': 0.9,
    'wmode': 4,
    'wscale': 2.2,
    'cx': -0.4,
    'cy': 0.3,
    'orbit': 0.5,
    'wave': 12,
    'wsize': 1.0,
    'remap': 4,
    'decay': 0.95,
    'hue_speed': 0.05
  }),
  _p('[full] lattice pulse', {
    'zoom': 1.02,
    'rot': 0.006,
    'warp': 0.35,
    'wmode': 3,
    'cx': 0.5,
    'cy': -0.4,
    'orbit': 0.4,
    'wave': 13,
    'wsize': 1.0,
    'remap': 1,
    'decay': 0.955,
    'hue_speed': 0.09
  }),
  _p('[full] diagonal storm', {
    'zoom': 1.01,
    'rot': -0.004,
    'warp': 0.8,
    'wmode': 2,
    'dx': 0.006,
    'dy': 0.006,
    'cx': -0.8,
    'cy': -0.6,
    'wave': 14,
    'wsize': 0.25,
    'remap': 2,
    'decay': 0.96
  }),
  _p('[full] aurora', {
    'zoom': 1.003,
    'rot': 0.0,
    'warp': 1.0,
    'wmode': 4,
    'wscale': 1.4,
    'dy': -0.006,
    'cy': -0.9,
    'orbit': 0.4,
    'wave': 10,
    'wsize': 0.12,
    'remap': 6,
    'decay': 0.975,
    'hue0': 0.4,
    'hue_speed': 0.03
  }),
  _p('[full] lava lamp', {
    'zoom': 0.998,
    'rot': 0.0,
    'warp': 1.2,
    'wmode': 4,
    'wscale': 1.2,
    'wspeed': 0.6,
    'dy': -0.004,
    'cx': 0.3,
    'cy': 0.5,
    'orbit': 0.6,
    'ospeed': 0.12,
    'wave': 12,
    'wsize': 1.0,
    'remap': 5,
    'decay': 0.955
  }),
  _p('[full] equalizer rain', {
    'zoom': 1.0,
    'warp': 0.3,
    'wmode': 2,
    'dy': 0.016,
    'dx': -0.003,
    'cy': -1.0,
    'orbit': 0.2,
    'wave': 11,
    'wsize': 0.7,
    'remap': 1,
    'decay': 0.962,
    'hue_speed': 0.12
  }),
  _p('[full] starfield wind', {
    'zoom': 1.035,
    'rot': 0.004,
    'warp': 0.2,
    'wmode': 0,
    'cx': 0.9,
    'cy': -0.3,
    'orbit': 0.3,
    'zexp': 1.6,
    'wave': 13,
    'wsize': 1.0,
    'remap': 6,
    'decay': 0.958
  }),
  _p('[full] neon grid melt', {
    'zoom': 1.008,
    'rot': -0.006,
    'warp': 0.9,
    'wmode': 3,
    'wscale': 2.8,
    'cx': -0.5,
    'cy': 0.4,
    'orbit': 0.35,
    'wave': 13,
    'wsize': 1.0,
    'remap': 7,
    'decay': 0.962
  }),
  _p('[full] crossfire', {
    'zoom': 1.018,
    'rot': 0.012,
    'warp': 0.5,
    'wmode': 1,
    'cx': 0.6,
    'cy': 0.6,
    'orbit': 0.3,
    'wave': 14,
    'wsize': 0.3,
    'remap': 4,
    'hue0': 0.08,
    'decay': 0.962
  }),
  _p('[full] tidal curtains', {
    'zoom': 0.99,
    'rot': 0.0,
    'warp': 0.7,
    'wmode': 3,
    'cx': -0.9,
    'cy': 0.2,
    'orbit': 0.25,
    'wave': 10,
    'wsize': 0.2,
    'remap': 3,
    'decay': 0.966
  }),
  _p('[full] solar plasma', {
    'zoom': 1.015,
    'rot': 0.01,
    'warp': 0.6,
    'wmode': 1,
    'cx': 0.7,
    'cy': -0.5,
    'orbit': 0.3,
    'wave': 12,
    'wsize': 1.0,
    'remap': 1,
    'decay': 0.952,
    'hue_speed': 0.1
  }),
];

const _adj = [
  'burning', 'drifting', 'broken', 'velvet', 'toxic', 'glass', 'midnight', 'electric', 'sunken', //
  'restless', 'crooked', 'silent', 'molten', 'frozen', 'hollow', 'wild', 'lonely', 'feral', 'liquid', 'static', //
  'violet', 'golden', 'haunted', 'distant'
];
const _noun = [
  'comet', 'harbor', 'nebula', 'engine', 'garden', 'signal', 'reef', 'tide', 'orbit', 'cathedral', //
  'highway', 'swamp', 'satellite', 'prism', 'furnace', 'dune', 'storm', 'lantern', 'glacier', 'circuit', //
  'mirage', 'abyss', 'meadow', 'ribbon'
];

/// Ещё 96 вариаций из «генов» ручных пресетов (как _generate на ПК): центр всегда смещён и блуждает.
List<MdPreset> _generate(int n, {int seed = 4242}) {
  final rng = math.Random(seed);
  final out = <MdPreset>[];
  final names = {for (final p in _manual) p.name};
  double u(double a, double b) => a + rng.nextDouble() * (b - a);
  const jitter = {'zoom': 0.01, 'rot': 0.012, 'warp': 0.25, 'wscale': 0.8, 'wspeed': 0.4, 'zexp': 0.4, 'decay': 0.006};
  while (out.length < n) {
    final a = _manual[rng.nextInt(_manual.length)];
    var b = _manual[rng.nextInt(_manual.length)];
    if (identical(a, b)) b = _manual[(_manual.indexOf(a) + 1) % _manual.length];
    final d = <String, double>{for (final k in _defaults.keys) k: (rng.nextBool() ? a.p : b.p)[k]!};
    jitter.forEach((k, j) => d[k] = a.p[k]! * 0.5 + b.p[k]! * 0.5 + u(-1, 1) * j);
    final ang = u(0, 2 * math.pi), rad = u(0.3, 0.9);
    d['cx'] = math.cos(ang) * rad * 1.3;
    d['cy'] = math.sin(ang) * rad;
    d['orbit'] = u(0.12, 0.45);
    d['ospeed'] = u(0.12, 0.4);
    if (d['wave']! < 10) {
      d['wx'] = d['cx']! * u(0.4, 0.9);
      d['wy'] = d['cy']! * u(0.4, 0.9);
    }
    d['aniso'] = rng.nextInt(3) < 2 ? 1.0 : u(0.96, 1.04);
    d['hue0'] = rng.nextDouble();
    d['zoom'] = d['zoom']!.clamp(0.975, 1.06);
    d['decay'] = d['decay']!.clamp(0.95, 0.982);
    d['warp'] = math.max(0.1, d['warp']!);
    var name = '${_adj[rng.nextInt(_adj.length)]} ${_noun[rng.nextInt(_noun.length)]}';
    if (d['wave']! >= 10) name = '[full] $name';
    if (!names.add(name)) continue;
    out.add(MdPreset(name, d));
  }
  return out;
}

/// Все пресеты (135), как на ПК.
final List<MdPreset> mdPresets = [..._manual, ..._generate(96)];

const _numKeys = [
  'zoom', 'rot', 'warp', 'wscale', 'wspeed', 'decay', 'zexp', 'dx', 'dy', 'cx', 'cy', 'orbit', //
  'ospeed', 'aniso', 'wsize', 'wx', 'wy', 'hue_speed'
];
const _discreteKeys = ['wave', 'remap', 'wmode', 'hue0'];

enum MdMode { auto, beat, lock }

/// «Звук» для MilkDrop: bass/mid/treb (≈1 — обычно, >1.4 — удар), их сглаженные версии, громкость,
/// спектр 48 полос и волна 512 точек. Ритм ~124 BPM, пока играет; на паузе всё плавно гаснет.
class _Audio {
  double bass = 0, mid = 0, treb = 0, bassAtt = 0, midAtt = 0, trebAtt = 0, vol = 0, _t = 0;
  final spec = Float32List(48);
  final wave = Float32List(512);
  final _rng = math.Random(7);
  double _ph1 = 0, _ph2 = 0, _ph3 = 0;

  void step(double dt, bool playing) {
    _t += dt;
    if (playing) {
      final beatPhase = (_t * 124 / 60) % 1.0;
      final kick = math.exp(-beatPhase * 9);
      final half = math.exp(-((_t * 124 / 30) % 1.0) * 14) * 0.35; // хэт на восьмые
      bass = 0.75 + 1.25 * kick + 0.12 * _rng.nextDouble();
      mid = 0.85 + 0.35 * math.sin(_t * 3.1) * math.sin(_t * 0.7) + 0.25 * _rng.nextDouble();
      treb = 0.8 + 0.6 * half + 0.35 * _rng.nextDouble() * _rng.nextDouble();
      vol += ((0.45 + 0.15 * math.sin(_t * 0.37) + 0.25 * kick) - vol) * 0.3;
      for (var i = 0; i < 48; i++) {
        final low = math.max(0.0, 1 - i / 10);
        final target =
            (0.22 + 0.45 * _rng.nextDouble()) * (1 - i / 48 * 0.55) + kick * low * 0.8 + half * (i > 30 ? 0.4 : 0);
        spec[i] += (target - spec[i]) * (target > spec[i] ? 0.6 : 0.2);
      }
      _ph1 += dt * (2.5 + 4 * _rng.nextDouble());
      _ph2 -= dt * (3 + 4 * _rng.nextDouble());
      _ph3 += dt * 2.3;
      var peak = 0.08;
      for (var j = 0; j < 512; j++) {
        final x = j / 512.0;
        // плавная «музыкальная» волна: низ (бас), середина, немного верха — без шума по точкам
        final v = math.sin(x * 12 + _ph1) * (0.45 + 0.45 * kick) +
            math.sin(x * 31 + _ph2) * 0.16 * treb +
            math.sin(x * 4.5 + _ph3) * 0.5 * bass * 0.6;
        wave[j] = v;
        peak = math.max(peak, v.abs());
      }
      for (var j = 0; j < 512; j++) {
        wave[j] /= peak;
      }
    } else {
      bass *= 0.85;
      mid *= 0.85;
      treb *= 0.85;
      vol *= 0.85;
      for (var i = 0; i < 48; i++) {
        spec[i] *= 0.85;
      }
      for (var j = 0; j < 512; j++) {
        wave[j] *= 0.8;
      }
    }
    bassAtt += (bass - bassAtt) * 0.25;
    midAtt += (mid - midAtt) * 0.25;
    trebAtt += (treb - trebAtt) * 0.25;
  }
}

/// Состояние и «физика» MilkDrop (без отрисовки): пресет, плавные переходы, центр, удары, кольца.
class MilkdropEngine {
  static const presetMin = 20.0, presetMax = 32.0, blendS = 4.0, beatMin = 9.0;
  final _rng = math.Random();
  final audio = _Audio();
  double t = 0;
  MdMode mode = MdMode.auto;
  int index;
  late MdParams p = Map.of(mdPresets[index].p);
  late MdParams _from = Map.of(p), _to = Map.of(p);
  double blend = 1, _presetT = 0, _presetLen = 26, _beatCool = 0, flash = 0;
  final rings = <List<double>>[]; // [x, y, r, alpha, hue]
  final _history = <int>[];
  int remapFrom = 1;

  MilkdropEngine({int? start}) : index = start ?? math.Random().nextInt(mdPresets.length) {
    remapFrom = p['remap']!.round();
  }

  String get name => mdPresets[index].name;
  double get hue => (t * p['hue_speed']! + p['hue0']!) % 1.0;

  void next([int? idx]) {
    if (idx == null) {
      final recent = _history.length > 12 ? _history.sublist(_history.length - 12) : _history;
      final choices = [
        for (var i = 0; i < mdPresets.length; i++)
          if (i != index && !recent.contains(i)) i
      ];
      idx = choices[_rng.nextInt(choices.length)];
    }
    _history.add(index);
    if (_history.length > 40) _history.removeAt(0);
    _go(idx);
  }

  void prev() {
    if (_history.isEmpty) return;
    _go(_history.removeLast());
  }

  void _go(int idx) {
    remapFrom = p['remap']!.round();
    index = idx % mdPresets.length;
    _from = Map.of(p);
    _to = Map.of(mdPresets[index].p);
    for (final (k, amt) in const [('zoom', 0.004), ('rot', 0.005), ('warp', 0.12), ('wscale', 0.3)]) {
      _to[k] = _to[k]! + (_rng.nextDouble() * 2 - 1) * amt;
    }
    blend = 0;
    _presetT = 0;
    _presetLen = presetMin + _rng.nextDouble() * (presetMax - presetMin);
  }

  (double, double) center() {
    final tt = t * p['ospeed']!;
    final o = p['orbit']!;
    return (
      p['cx']! + o * (math.sin(tt) * 0.8 + math.sin(tt * 2.37 + 1.3) * 0.35),
      p['cy']! + o * 0.7 * (math.cos(tt * 0.83 + 0.4) * 0.8 + math.sin(tt * 1.91) * 0.3),
    );
  }

  /// Шаг «физики»; aspect — ширина/высота буфера (для колец).
  void step(double dt, bool playing, double aspect) {
    dt = dt.clamp(0.001, 0.1);
    t += dt;
    audio.step(dt, playing);
    final a = audio;
    // пресеты
    _presetT += dt;
    if (mode == MdMode.auto && _presetT >= _presetLen) next();
    if (mode == MdMode.beat && _presetT >= beatMin) {
      if ((a.bass > 1.75 && a.bass > a.bassAtt * 1.25) || _presetT > 45) next();
    }
    if (blend < 1) {
      blend = math.min(1, blend + dt / blendS);
      final k = blend * blend * (3 - 2 * blend);
      for (final key in _numKeys) {
        p[key] = _from[key]! * (1 - k) + _to[key]! * k;
      }
      final src = blend >= 0.5 ? _to : _from;
      for (final key in _discreteKeys) {
        p[key] = src[key]!;
      }
    }
    // удар баса: вспышка и кольцо в случайном месте
    _beatCool -= dt;
    final (cx, cy) = center();
    if (a.bass > 1.45 && a.bass > a.bassAtt * 1.12 && _beatCool <= 0) {
      _beatCool = 0.22;
      flash = math.min(0.35, 0.10 + (a.bass - 1.4) * 0.25);
      rings.add([
        cx * 0.5 + (_rng.nextDouble() * 1.2 - 0.6) * aspect,
        cy * 0.5 + (_rng.nextDouble() * 1.2 - 0.6),
        0.05,
        0.9,
        t * p['hue_speed']! + p['hue0']! + 0.5,
      ]);
      if (rings.length > 6) rings.removeAt(0);
    }
  }

  /// Значения для md_warp.frag на этот шаг (f = dt·30, как на ПК).
  List<double> warpUniforms(double dt, double bufW, double bufH) {
    final f = dt.clamp(0.001, 0.1) * 30;
    final a = audio;
    final (cx, cy) = center();
    final zoom = p['zoom']! + (a.bassAtt > 0.2 ? (a.bassAtt - 1.0) * 0.018 : 0);
    final lz = math.log(math.max(0.5, zoom)) * f;
    final rot = (p['rot']! + (a.midAtt > 0.2 ? (a.midAtt - 1.0) * 0.008 : 0)) * f;
    final an = math.pow(p['aniso']!, f).toDouble();
    final wa = p['warp']! * (0.012 + 0.02 * math.min(2.0, a.trebAtt)) * f;
    final decay = math.min(0.995, p['decay']! + 0.006 * math.min(1.0, a.vol));
    final fl = flash;
    if (flash > 0.002) flash *= math.pow(0.55, f);
    return [
      bufW, bufH, lz, p['zexp']!, rot, an, wa, p['wscale']!, t * p['wspeed']!, p['wmode']!, //
      cx, cy, p['dx']! * f * (0.6 + 0.4 * math.sin(t * 0.21)), p['dy']! * f, //
      math.pow(decay, f).toDouble(), 0.011 * f, fl,
    ];
  }
}

/// Рисование волны (и колец) в буфер — те же 15 видов, что на ПК. Координаты: x ∈ [-A, A], y ∈ [-1, 1],
/// y вниз. Цвета складываются «максимумом» (BlendMode.lighten), как np.maximum на ПК.
class MdWaveDrawer {
  final MilkdropEngine e;
  final Canvas c;
  final double w, h, aspect;
  final _rng = math.Random();
  MdWaveDrawer(this.e, this.c, this.w, this.h) : aspect = w / h;

  Offset _pt(double x, double y) => Offset((x / aspect * 0.5 + 0.5) * w, (y * 0.5 + 0.5) * h);

  Paint _paint(Color col, [double thick = 2]) => Paint()
    ..color = col
    ..strokeWidth = thick
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.lighten
    ..style = PaintingStyle.stroke;

  static Color hsv(double h, double s, double v, [double mul = 1]) {
    final hh = (h % 1.0) * 6;
    final i = hh.floor() % 6;
    final f = hh - hh.floor();
    final p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
    final (r, g, b) = switch (i) {
      0 => (v, t, p),
      1 => (q, v, p),
      2 => (p, v, t),
      3 => (p, q, v),
      4 => (t, p, v),
      _ => (v, p, q),
    };
    return Color.from(alpha: 1, red: (r * mul).clamp(0, 1), green: (g * mul).clamp(0, 1), blue: (b * mul).clamp(0, 1));
  }

  void _line(List<Offset> pts, Color col, [double thick = 2]) {
    if (pts.length < 2) return;
    c.drawPoints(PointMode.polygon, pts, _paint(col, thick));
  }

  void _dots(List<Offset> pts, Color col, [double thick = 2]) =>
      c.drawPoints(PointMode.points, pts, _paint(col, thick));

  void draw() {
    final a = e.audio, p = e.p;
    var ww = a.wave;
    if (!ww.any((v) => v.abs() > 1e-3) && a.vol < 0.01) {
      ww = Float32List.fromList([for (var j = 0; j < 512; j++) 0.15 * math.sin(j / 512 * 6 * math.pi + e.t * 2)]);
    }
    final hue = e.hue;
    final bright = 0.55 + 0.65 * math.min(1.0, a.vol * 1.5 + 0.2);
    final col = hsv(hue, 0.85, 1, bright), col2 = hsv(hue + 0.37, 0.85, 1, bright);
    final size = p['wsize']! * (1.0 + (a.bassAtt > 0.2 ? 0.25 * (a.bassAtt - 1.0) : 0));
    final mode = p['wave']!.round();
    const n = 256;
    double wv(int i) => ww[(i * 2) % 512];
    final (cx, cy) = e.center();
    final ox = p['wx']! + 0.35 * (cx - p['cx']!), oy = p['wy']! + 0.35 * (cy - p['cy']!);
    final A = aspect, t = e.t;

    switch (mode) {
      case 0: // круг (не в центре)
        _line([
          for (var i = 0; i <= n; i++)
            () {
              final ang = i / n * 2 * math.pi + t * 0.3;
              final r = size * (1 + 0.45 * wv(i % n));
              return _pt(ox + math.cos(ang) * r * 1.15, oy + math.sin(ang) * r * 0.85);
            }()
        ], col);
      case 1: // линия с наклоном
        final ang = 0.25 + math.sin(t * 0.23) * 0.5, cs = math.cos(ang), sn = math.sin(ang);
        _line([
          for (var i = 0; i < n; i++)
            () {
              final x = -A * 0.95 + i / (n - 1) * A * 1.9, y = wv(i) * size;
              return _pt(ox + x * cs - y * sn, oy + x * sn + y * cs);
            }()
        ], col);
      case 2: // XY-осциллограф
        _line(
            [for (var i = 0; i < 240; i++) _pt(ox + ww[i * 2] * size * 1.6, oy + ww[(i * 2 + 13) % 512] * size * 1.2)],
            col);
      case 3: // две несимметричные линии
        final off = 0.3 + 0.1 * math.sin(t * 0.5);
        _line([
          for (var i = 0; i < n; i++)
            () {
              final x = -A * 0.95 + i / (n - 1) * A * 1.9;
              return _pt(x, oy + off + wv(i) * size * 0.6 + x * 0.12);
            }()
        ], col);
        _line([
          for (var i = 0; i < n; i++)
            () {
              final x = -A * 0.95 + i / (n - 1) * A * 1.9;
              return _pt(x * 0.8 + 0.2, oy - off * 0.6 - wv(n - 1 - i) * size * 0.4);
            }()
        ], col2);
      case 4: // лучи — спектр по кругу
        for (var k = 0; k < 24; k++) {
          final ang = k / 24 * 2 * math.pi + t * 0.4;
          final r0 = size * 0.25, r1 = size * (0.3 + 1.4 * a.spec[k * 2]);
          c.drawLine(_pt(ox + math.cos(ang) * r0, oy + math.sin(ang) * r0 * 0.8),
              _pt(ox + math.cos(ang) * r1, oy + math.sin(ang) * r1 * 0.8), _paint(hsv(hue + k / 24, 0.9, 1, bright)));
        }
      case 5: // спираль
        _line([
          for (var i = 0; i < n; i++)
            () {
              final th = i / (n - 1) * 5 * math.pi;
              final r = size * (0.08 + th / (5 * math.pi)) * (1 + 0.35 * wv(i));
              final ang = th + t * 0.9;
              return _pt(ox + math.cos(ang) * r * 1.2, oy + math.sin(ang) * r);
            }()
        ], col);
      case 6: // искры от излучателя
        final cnt = (30 + 140 * math.min(1.5, a.trebAtt) * math.min(1.0, a.vol * 2 + 0.1)).round();
        final ex = ox + 0.25 * math.sin(t * 0.7), ey = oy + 0.2 * math.cos(t * 0.53);
        for (var g = 0; g < 4; g++) {
          final pts = <Offset>[];
          for (var i = 0; i < cnt ~/ 4; i++) {
            final ang = _rng.nextDouble() * 2 * math.pi;
            final rad = math.pow(_rng.nextDouble(), 2) * size * (0.6 + a.bassAtt * 0.5);
            pts.add(_pt(ex + math.cos(ang) * rad * 1.3, ey + math.sin(ang) * rad));
          }
          _dots(pts, hsv(hue + g * 0.06, 0.9, 1, bright));
        }
      case 7: // спектр от левого края
        final x0 = -A * 0.98 + (ox + A) * 0.15;
        for (var k = 0; k < 40; k++) {
          final y = -0.9 + k / 39 * 1.8 + oy * 0.2;
          c.drawLine(
              _pt(x0, y), _pt(x0 + size * 2.2 * a.spec[k] * A, y), _paint(hsv(hue + k / 39 * 0.5, 0.9, 1, bright)));
        }
      case 8: // орбиты
        final bands = [a.bassAtt, a.midAtt, a.trebAtt, a.bass, a.mid];
        for (var i = 0; i < bands.length; i++) {
          final ro = size * (0.35 + i * 0.28);
          final ph = t * (0.6 + i * 0.37) * (i.isOdd ? 1 : -1) + i;
          final px = ox + math.cos(ph) * ro * 1.3, py = oy + math.sin(ph) * ro * 0.8;
          final rr = 0.03 + 0.05 * math.min(2.0, bands[i]);
          _line([
            for (var j = 0; j <= 48; j++)
              _pt(px + math.cos(j / 48 * 2 * math.pi) * rr, py + math.sin(j / 48 * 2 * math.pi) * rr)
          ], hsv(hue + i * 0.13, 0.85, 1, bright));
        }
      case 9: // комета-лиссажу
        final pts = <Offset>[];
        for (var i = 0; i < n; i++) {
          final tt = t - 0.6 + i / (n - 1) * 0.6;
          pts.add(_pt(ox + math.sin(tt * 1.3) * size * 1.6 + wv(i) * 0.05,
              oy + math.sin(tt * 1.9 + 0.7) * size + wv(n - 1 - i) * 0.05));
        }
        for (var s = 0; s < 4; s++) {
          final seg = pts.sublist(s * n ~/ 4, math.min(n, (s + 1) * n ~/ 4 + 1));
          _line(seg, hsv(hue + s * 0.08, 0.85, 1, bright * (0.25 + 0.25 * s)));
        }
        _line(pts.sublist(n - 40), col, 3);
      case 10: // занавес волн
        for (var r = 0; r < 6; r++) {
          final yb = -0.92 + 1.84 * (r + 0.5) / 6 + 0.08 * math.sin(t * 0.4 + r * 1.7);
          final amp = size * (0.6 + 0.8 * a.spec[r * 7 % 48]);
          _line([
            for (var i = 0; i < n; i++)
              () {
                final x = -A + i / (n - 1) * 2 * A;
                return _pt(
                    x, yb + wv((i + r * 37) % n) * amp + 0.05 * math.sin(x * (1.3 + r * 0.4) + t * (0.5 + r * 0.13)));
              }()
          ], hsv(hue + r / 6 * 0.6, 0.85, 1, bright));
        }
      case 11: // спектр-пол на всю ширину
        for (var k = 0; k < 48; k++) {
          final x = -A * 0.98 + k / 47 * A * 1.96;
          c.drawLine(
              _pt(x, 0.98), _pt(x, 0.98 - size * 1.9 * a.spec[k]), _paint(hsv(hue + k / 47 * 0.7, 0.9, 1, bright), 3));
        }
      case 12: // плазма (крупными «пикселями») + волна поверх
        const gx = 24, gy = 40;
        final k = 0.08 + 0.22 * math.min(1.5, a.vol * 2) + 0.1 * math.max(0.0, a.bass - 1.0);
        final cell = Size(w / gx + 0.5, h / gy + 0.5);
        for (var yy = 0; yy < gy; yy++) {
          for (var xx = 0; xx < gx; xx++) {
            final px = (xx / (gx - 1) * 2 - 1) * A, py = yy / (gy - 1) * 2 - 1;
            final fld = math.sin(px * 2.1 + t * 0.9) +
                math.sin(py * 3.3 - t * 1.2 + px * 0.7) +
                math.sin((px + py * 1.4) * 2.6 + t * 0.6) +
                math.sin(math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)) * 5 - t * 2);
            final band = (1 - (fld - 1.2 * math.sin(t * 0.3)).abs() * 2.2).clamp(0.0, 1.0);
            if (band < 0.02) continue;
            c.drawRect(
                Offset(xx * w / gx, yy * h / gy) & cell,
                Paint()
                  ..color = hsv(hue, 0.8, 1, band * k)
                  ..blendMode = BlendMode.lighten);
          }
        }
        _line([for (var i = 0; i < n; i++) _pt(ox + (-A + i / (n - 1) * 2 * A) * 0.9, oy + wv(i) * size * 0.35)],
            hsv(hue, 0.85, 1, bright * 0.8));
      case 13: // решётка точек
        for (var yy = 0; yy < 15; yy++) {
          final pts = <Offset>[];
          var lv = 0.0;
          for (var xx = 0; xx < 26; xx++) {
            final x = -A * 0.95 + xx / 25 * A * 1.9, y = -0.92 + yy / 14 * 1.84;
            final lev = a.spec[((x + A) / (2 * A) * 47).round().clamp(0, 47)];
            if (lev <= 0.25 + 0.15 * math.sin(x * 3 + y * 2 + t)) continue;
            final jit = 0.04 * math.sin(y * 5 + t * 2 + x * 1.7);
            pts.add(_pt(x + jit, y + jit * 0.7));
            lv = math.max(lv, lev);
          }
          if (pts.isNotEmpty) _dots(pts, hsv(hue + (yy / 14 * 1.84) * 0.25, 0.9, 1, bright * lv.clamp(0.3, 1.0)), 3);
        }
      default: // 14: диагонали через весь кадр
        for (var i = 0; i < 3; i++) {
          final ang = 0.5 + i * 0.9 + math.sin(t * 0.17 + i) * 0.4, cs = math.cos(ang), sn = math.sin(ang);
          final off = (i - 1) * 0.45 + 0.15 * math.sin(t * 0.31 + i * 2);
          _line([
            for (var j = 0; j < n; j++)
              () {
                final l = -2.2 + j / (n - 1) * 4.4;
                final sg = wv((j + i * 61) % n) * size;
                return _pt(l * cs - (off + sg) * sn + cx * 0.3, l * sn + (off + sg) * cs + cy * 0.3);
              }()
          ], hsv(hue + i * 0.21, 0.85, 1, bright));
        }
    }
  }

  /// Кольца от ударов баса: расходятся и гаснут.
  void rings(double dt) {
    final keep = <List<double>>[];
    for (final r in e.rings) {
      _line([
        for (var j = 0; j <= 96; j++)
          _pt(r[0] + math.cos(j / 96 * 2 * math.pi) * r[2] * 1.2, r[1] + math.sin(j / 96 * 2 * math.pi) * r[2] * 0.9)
      ], hsv(r[4], 0.9, 1, r[3]));
      r[2] += dt * 1.1;
      r[3] *= math.pow(0.86, dt * 30);
      if (r[3] > 0.05 && r[2] < 1.6) keep.add(r);
    }
    e.rings
      ..clear()
      ..addAll(keep);
  }
}
