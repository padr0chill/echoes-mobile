import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../cover_color.dart';
import '../glass.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/store.dart';
import '../services/wave.dart';
import '../ui.dart';
import '../widgets.dart';
import 'artist_screen.dart';

/// «Моя волна» в духе Яндекс Музыки: живое «пламя» на весь экран, по центру — «▶ Моя волна»
/// и кнопка «Настроить», внизу — капсулы с быстрыми волнами. Цвет пламени — от настроения.
class WaveScreen extends StatelessWidget {
  const WaveScreen({super.key});

  static const _moods = <String, (IconData, String, List<Color>)>{
    'Энергичное': (
      Icons.bolt_rounded,
      'Бодрый ритм',
      [Color(0xFFFFF04D), Color(0xFFFF7A00), Color(0xFFFF1F3D), Color(0xFFC2005E)]
    ),
    'Спокойное': (
      Icons.spa_rounded,
      'Мягко и ровно',
      [Color(0xFFA8F4FF), Color(0xFF3EC8FF), Color(0xFF4060FF), Color(0xFF7A3CFF)]
    ),
    'Грустное': (
      Icons.water_drop_rounded,
      'Под настроение',
      [Color(0xFFC4CEFF), Color(0xFF7480FF), Color(0xFF5A3DB8), Color(0xFF2B1E66)]
    ),
    'Тренировка': (
      Icons.fitness_center_rounded,
      'Не сбавляй темп',
      [Color(0xFFE2FF3D), Color(0xFF3DFF8A), Color(0xFF00C2A8), Color(0xFF0077FF)]
    ),
    'Для сна': (
      Icons.bedtime_rounded,
      'Тихо и медленно',
      [Color(0xFFD6C9FF), Color(0xFF8A6CFF), Color(0xFF3D2C8F), Color(0xFF1A1446)]
    ),
    'Русский рэп': (
      Icons.mic_rounded,
      'Свежее и любимое',
      [Color(0xFFFFD43B), Color(0xFFFF4D4D), Color(0xFFB3001B), Color(0xFF5A0016)]
    ),
  };

  /// Пламя «под вас» — из цвета акцента: акцент → теплее → краснее → пурпур (жёлтый даёт как у Яндекса).
  static List<Color> _accentPalette(Color a) {
    final h = HSLColor.fromColor(a);
    Color c(double dh, double l) => HSLColor.fromAHSL(1, (h.hue + dh) % 360, math.max(0.85, h.saturation), l).toColor();
    return [c(0, 0.62), c(-25, 0.55), c(-50, 0.52), c(-85, 0.42)];
  }

  static List<Color> paletteFor(String? mood, Color accent) => _moods[mood]?.$3 ?? _accentPalette(accent);

  void _tune(BuildContext context) {
    final w = Wave.instance;
    showGlassSheet(context, (ctx) {
      Widget tile(String? m, IconData icon, String label, String sub, List<Color> pal) {
        final selected = w.active && w.mood == m;
        return InkWell(
          borderRadius: BorderRadius.circular(ctx.u(18)),
          onTap: () {
            Navigator.pop(ctx);
            w.start(mood: m);
          },
          child: Container(
            padding: EdgeInsets.all(ctx.u(10)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ctx.u(18)),
              color: selected ? pal[1].withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: selected ? pal[1] : Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(children: [
              _Orb(colors: pal, icon: icon, size: ctx.u(38)),
              SizedBox(width: ctx.u(10)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(ctx).textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
                ]),
              ),
            ]),
          ),
        );
      }

      final twoCols = MediaQuery.sizeOf(ctx).width >= 360;
      final tiles = [
        tile(null, Icons.all_inclusive_rounded, 'Под вас', 'По лайкам и истории', _accentPalette(ctx.accent)),
        for (final e in _moods.entries) tile(e.key, e.value.$1, e.key, e.value.$2, e.value.$3),
      ];
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Настроить волну', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        SizedBox(height: ctx.u(4)),
        Text('Выберите настроение — волна сразу перестроится',
            style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
        SizedBox(height: ctx.u(14)),
        if (twoCols)
          for (var i = 0; i < tiles.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: ctx.u(8)),
              child: Row(children: [
                Expanded(child: tiles[i]),
                SizedBox(width: ctx.u(8)),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
              ]),
            )
        else
          for (final t in tiles) Padding(padding: EdgeInsets.only(bottom: ctx.u(8)), child: t),
        if (w.active)
          Center(
            child: TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                w.stop();
              },
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Остановить волну'),
            ),
          ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = Wave.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([w, audio.index, Store.instance]),
      builder: (context, _) {
        final active = w.active;
        final t = active ? audio.current : null;
        final pal = paletteFor(active ? w.mood : null, context.accent);
        final bottom = MediaQuery.paddingOf(context).bottom;
        return Stack(children: [
          Positioned.fill(child: _Flame(colors: pal, track: t)),
          SafeArea(
            bottom: false,
            child: Column(children: [
              // верхняя строка: логотип и поиск, как в Яндекс Музыке
              Padding(
                padding: EdgeInsets.fromLTRB(context.u(16), context.u(8), context.u(12), 0),
                child: Row(children: [
                  SizedBox(width: context.u(44)),
                  Expanded(
                    child: Center(
                      child: Text('ECHOES',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2, color: context.accent)),
                    ),
                  ),
                  GlassIconButton(icon: Icons.search_rounded, tooltip: 'Поиск', onTap: () => openTab.value = 1),
                ]),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _Title(active: active, loading: w.loading),
                        SizedBox(height: context.u(14)),
                        _TunePill(mood: active ? w.mood : null, onTap: () => _tune(context)),
                        if (t != null) ...[
                          SizedBox(height: context.u(22)),
                          _NowPlaying(track: t),
                        ],
                        if (w.error != null)
                          Padding(
                            padding: EdgeInsets.all(context.u(16)),
                            child: Glass(
                              radius: context.u(16),
                              padding: EdgeInsets.all(context.u(12)),
                              child: Text(w.error!,
                                  textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80))),
                            ),
                          ),
                      ]),
                    ),
                  );
                }),
              ),
              _Capsules(onTune: () => _tune(context)),
              // место под мини-плеер и панель вкладок
              SizedBox(height: context.wide ? context.u(90) : context.u(150) + bottom),
            ]),
          ),
        ]);
      },
    );
  }
}

/// «▶ Моя волна» — крупно, по центру; нажатие запускает волну или ставит на паузу.
class _Title extends StatelessWidget {
  final bool active;
  final bool loading;
  const _Title({required this.active, required this.loading});

  @override
  Widget build(BuildContext context) {
    final w = Wave.instance;
    return StreamBuilder<bool>(
      stream: audio.player.playingStream,
      builder: (context, snap) {
        final playing = active && (snap.data ?? false);
        return Semantics(
          button: true,
          label: playing ? 'Пауза' : 'Запустить волну',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (w.loading) return;
              if (active) {
                playing ? audio.pause() : audio.play();
              } else {
                w.start();
              }
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(8)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: loading
                        ? SizedBox(
                            key: const ValueKey('l'),
                            width: context.u(34),
                            height: context.u(34),
                            child: const CircularProgressIndicator(strokeWidth: 3.5, color: Colors.white),
                          )
                        : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            key: ValueKey(playing), size: context.u(52), color: Colors.white),
                  ),
                  SizedBox(width: context.u(6)),
                  Text('Моя волна',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18)],
                      )),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Полупрозрачная пилюля «≡ Настроить» (с выбранным настроением).
class _TunePill extends StatelessWidget {
  final String? mood;
  final VoidCallback onTap;
  const _TunePill({required this.mood, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Настроить волну',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: context.u(18), vertical: context.u(10)),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.tune_rounded, size: context.u(18), color: Colors.white),
              SizedBox(width: context.u(8)),
              Text(mood == null ? 'Настроить' : 'Настроить · $mood',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Нижняя лента капсул: «Для вас», быстрые настроения, «Ещё».
class _Capsules extends StatelessWidget {
  final VoidCallback onTune;
  const _Capsules({required this.onTune});

  @override
  Widget build(BuildContext context) {
    final w = Wave.instance;
    final top = Store.instance.topArtists(2);
    final items = <(Widget, String, String, VoidCallback)>[
      (
        _Orb(colors: WaveScreen._accentPalette(context.accent), icon: Icons.auto_awesome_rounded, size: context.u(40)),
        'Для вас',
        top.isEmpty ? 'Подборки по вкусу' : top.join(', '),
        () => openTab.value = 2,
      ),
      for (final e in WaveScreen._moods.entries)
        (
          _Orb(colors: e.value.$3, icon: e.value.$1, size: context.u(40)),
          e.key,
          e.value.$2,
          () => w.loading ? null : w.start(mood: e.key),
        ),
      (
        _Orb(
            colors: const [Color(0xFF9E9E9E), Color(0xFF616161), Color(0xFF424242), Color(0xFF212121)],
            icon: Icons.tune_rounded,
            size: context.u(40)),
        'Ещё',
        'Все настройки',
        onTune,
      ),
    ];
    // высота — по кружку или по двум строкам текста (что больше), содержимое — строго по центру
    final h = math.max(context.u(52), MediaQuery.textScalerOf(context).scale(38) + context.u(12));
    return SizedBox(
      height: h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.u(12)),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: context.u(8)),
        itemBuilder: (context, i) {
          final (orb, title, sub, onTap) = items[i];
          final selected = w.active && w.mood == title;
          return GestureDetector(
            onTap: onTap,
            child: Glass(
              radius: h / 2,
              blur: 18,
              tint: selected ? 1.6 : 1.0,
              shadow: false,
              padding: EdgeInsets.fromLTRB(context.u(6), 0, context.u(18), 0),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  orb,
                  SizedBox(width: context.u(10)),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: context.u(150)),
                    child:
                        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.65))),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Круглый «шарик» с градиентом палитры и значком.
class _Orb extends StatelessWidget {
  final List<Color> colors;
  final IconData icon;
  final double size;
  const _Orb({required this.colors, required this.icon, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors, center: const Alignment(-0.3, -0.4), radius: 1.1),
      ),
      child: Icon(icon, size: size * 0.5, color: Colors.white),
    );
  }
}

/// «Плазма», как у волны Яндекс Музыки: облако цвета обложки текущего трека (или настроения) с яркими
/// тонкими «нитями», которые медленно извиваются; пока играет — быстрее и «дышит». Смена трека —
/// плавный перелив в новый цвет.
class _Flame extends StatefulWidget {
  final List<Color> colors; // цвета, пока нет обложки (настроение / акцент)
  final Track? track;
  const _Flame({required this.colors, this.track});

  @override
  State<_Flame> createState() => _FlameState();
}

class _FlameState extends State<_Flame> with TickerProviderStateMixin {
  late final AnimationController _time = AnimationController(vsync: this, duration: const Duration(seconds: 40))
    ..repeat();
  late final AnimationController _mix = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..value = 1;
  late List<Color> _from = widget.colors;
  late List<Color> _to = widget.colors;
  List<Color>? _cover;
  double _phase = 0, _last = 0, _energy = 0;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(_Flame old) {
    super.didUpdateWidget(old);
    if (old.track?.id != widget.track?.id) {
      _cover = null;
      _loadCover();
    }
    _retarget();
  }

  Future<void> _loadCover() async {
    final t = widget.track;
    if (t == null) return;
    final c = await coverColor(t);
    if (!mounted || widget.track?.id != t.id) return;
    _cover = c == null ? null : paletteFromColor(c);
    _retarget();
  }

  void _retarget() {
    final target = _cover ?? widget.colors;
    if (_same(target, _to)) return;
    _from = _current();
    _to = target;
    _mix.forward(from: 0);
  }

  static bool _same(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<Color> _current() {
    final k = Curves.easeInOut.transform(_mix.value);
    return [for (var i = 0; i < _to.length; i++) Color.lerp(_from[i], _to[i], k)!];
  }

  @override
  void dispose() {
    _time.dispose();
    _mix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: StreamBuilder<bool>(
          stream: audio.player.playingStream,
          builder: (context, snap) {
            final playing = (snap.data ?? false) && Wave.instance.active;
            return AnimatedBuilder(
              animation: Listenable.merge([_time, _mix]),
              builder: (context, _) {
                // время копится: при игре течёт быстрее, без рывков; «энергия» плавно растёт/спадает
                var d = _time.value - _last;
                if (d < 0) d += 1;
                _last = _time.value;
                _phase += d * (1 + 2.2 * _energy);
                _energy += ((playing ? 1.0 : 0.0) - _energy) * 0.04;
                return CustomPaint(
                  painter: _FlamePainter(_phase * 2 * math.pi, _current(), _energy),
                  size: Size.infinite,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  final double t;
  final List<Color> c;
  final double energy;
  _FlamePainter(this.t, this.c, this.energy);

  /// Бесформенное пятно: окружность, радиус которой «колышется» гармониками.
  Path _blob(Offset o, double r, double seed) {
    final p = Path();
    const n = 48;
    for (var i = 0; i <= n; i++) {
      final a = i / n * 2 * math.pi;
      final k = 1 +
          0.16 * math.sin(3 * a + t * 1.3 + seed) +
          0.10 * math.sin(5 * a - t * 1.7 + seed * 2) +
          0.06 * math.sin(2 * a + t * 0.9 + seed * 3);
      final pt = o + Offset(math.cos(a), math.sin(a)) * r * k;
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  /// Нить плазмы: от ядра наружу, изгибается и «плывёт».
  Path _wisp(Offset o, double s, int i) {
    final base = i / 9 * 2 * math.pi + math.sin(t * 0.3 + i) * 0.5;
    final len = s * (0.42 + 0.12 * math.sin(t * 0.7 + i * 1.9));
    Offset at(double f, double bend) {
      final a = base + bend * math.sin(t * (0.8 + i * 0.07) + f * 3 + i);
      return o + Offset(math.cos(a), math.sin(a)) * len * f;
    }

    final p0 = at(0.08, 0.2), p1 = at(0.4, 0.6), p2 = at(0.7, 0.9), p3 = at(1.0, 1.1);
    return Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final s = math.min(w, h * 0.75);
    final center = Offset(w / 2, h * 0.40);
    final beat = 1 + energy * 0.05 * math.sin(t * 9);
    // широкое свечение края экрана цветом трека (как заливка фона у Яндекса)
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.1,
          colors: [c[2].withValues(alpha: 0.55), c[3].withValues(alpha: 0.35), c[3].withValues(alpha: 0)],
          stops: const [0, 0.55, 1],
        ).createShader(Offset.zero & size),
    );
    // облако: слои снаружи внутрь — тёмный край → глубже → основной цвет → светлое ядро
    final layers = [
      (c[3], 0.66, 0.20, 0.0, 0.85),
      (c[2], 0.52, 0.16, 1.7, 0.95),
      (c[1], 0.40, 0.13, 3.1, 1.0),
      (c[1], 0.30, 0.18, 5.3, 0.8),
      (c[0], 0.24, 0.10, 4.6, 1.0),
    ];
    for (final (color, r, drift, seed, alpha) in layers) {
      final o = center + Offset(math.sin(t * 0.7 + seed) * s * drift, math.cos(t * 0.5 + seed * 1.3) * s * drift * 0.8);
      final rad = s * r * beat;
      canvas.drawPath(
        _blob(o, rad, seed),
        Paint()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.35)
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: alpha * 0.55), color.withValues(alpha: 0)],
            stops: const [0, 0.6, 1],
          ).createShader(Rect.fromCircle(center: o, radius: rad * 1.25)),
      );
    }
    // нити: широкое мягкое свечение + тонкая яркая середина
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.03
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.025)
      ..color = Color.lerp(c[0], Colors.white, 0.5)!.withValues(alpha: 0.18 + 0.12 * energy);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, s * 0.004)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.003)
      ..color = Color.lerp(c[0], Colors.white, 0.75)!.withValues(alpha: 0.30 + 0.25 * energy);
    for (var i = 0; i < 9; i++) {
      final path = _wisp(center, s, i);
      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
    }
    // светлое ядро
    final core = center + Offset(math.sin(t * 1.1) * s * 0.05, math.cos(t * 0.8) * s * 0.04);
    canvas.drawCircle(
      core,
      s * 0.13,
      Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.09)
        ..color = Color.lerp(c[0], Colors.white, 0.55)!.withValues(alpha: 0.40 + 0.15 * energy),
    );
  }

  @override
  bool shouldRepaint(_FlamePainter old) => true;
}

/// Смена трека: старое расплывается и тает, новое проступает из размытия (как заголовок у Яндекса).
Widget _blurSwitch(Widget child, Animation<double> a) => AnimatedBuilder(
      animation: a,
      child: child,
      builder: (context, child) {
        final v = Curves.easeOut.transform(a.value);
        return Opacity(
          opacity: v,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: (1 - v) * 10, sigmaY: (1 - v) * 10),
            child: Transform.scale(scale: 0.94 + 0.06 * v, child: child),
          ),
        );
      },
    );

/// Текущий трек волны: маленькая обложка, название в стеклянной плашке, исполнитель — ссылка.
class _NowPlaying extends StatelessWidget {
  final Track track;
  const _NowPlaying({required this.track});

  @override
  Widget build(BuildContext context) {
    final t = track;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      transitionBuilder: _blurSwitch,
      child: Column(key: ValueKey(t.id), mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(context.u(12)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))
            ],
          ),
          child: Cover(track: t, size: context.u(72), radius: context.u(12)),
        ),
        SizedBox(height: context.u(12)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.u(28)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: context.u(20), vertical: context.u(9)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ),
        GestureDetector(
          onTap: () => openArtist(context, t),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.u(32), vertical: context.u(6)),
            child: Text(t.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}
