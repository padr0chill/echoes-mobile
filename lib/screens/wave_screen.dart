import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
              blur: 0, // поверх анимации размытие пересчитывалось бы каждый кадр — заливки достаточно
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

/// «Плазма», как у волны Яндекс Музыки: облако цвета обложки текущего трека (или настроения),
/// по нему текут мягкие прожилки света («каустики»). Рисует шейдер на видеокарте (shaders/wave.frag);
/// кадры идут через repaint, без перестройки виджетов. Пока играет — течёт быстрее и «дышит».
/// Смена трека — плавный перелив цвета.
class _Flame extends StatefulWidget {
  final List<Color> colors; // цвета, пока нет обложки (настроение / акцент)
  final Track? track;
  const _Flame({required this.colors, this.track});

  @override
  State<_Flame> createState() => _FlameState();
}

class _FlameState extends State<_Flame> with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram?>? _program;
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  Duration _prev = Duration.zero;
  double _time = 0, _energy = 0, _mixT = 1;
  bool _playing = false;
  StreamSubscription<bool>? _sub;
  late List<Color> _from = widget.colors;
  late List<Color> _to = widget.colors;
  List<Color>? _cover;

  @override
  void initState() {
    super.initState();
    _program ??=
        ui.FragmentProgram.fromAsset('shaders/wave.frag').then<ui.FragmentProgram?>((p) => p).catchError((_) => null);
    _program!.then((p) {
      if (mounted && p != null) setState(() => _shader = p.fragmentShader());
    });
    _sub = audio.player.playingStream.listen((v) => _playing = v);
    _ticker = createTicker(_onTick)..start();
    _loadCover();
  }

  void _onTick(Duration now) {
    final dt = ((now - _prev).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _prev = now;
    final playing = _playing && Wave.instance.active;
    _energy += ((playing ? 1.0 : 0.0) - _energy) * (1 - math.exp(-dt * 2.5));
    _time += dt * (1 + 1.6 * _energy);
    if (_mixT < 1) _mixT = math.min(1, _mixT + dt / 1.4);
    _frame.value++;
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
    _mixT = 0;
  }

  static bool _same(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<Color> _current() {
    final k = Curves.easeInOut.transform(_mixT);
    return [for (var i = 0; i < _to.length; i++) Color.lerp(_from[i], _to[i], k)!];
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _shader != null
              ? _ShaderPainter(_frame, _shader!, () => (_time, _energy, _current()))
              : _BlobPainter(_frame, () => (_time, _energy, _current())),
        ),
      ),
    );
  }
}

typedef _FlameState3 = (double, double, List<Color>) Function();

class _ShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final _FlameState3 state;
  _ShaderPainter(Listenable frame, this.shader, this.state) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    final (t, e, c) = state();
    var i = 0;
    void f(double v) => shader.setFloat(i++, v);
    f(size.width);
    f(size.height);
    f(t);
    f(e);
    for (final col in c) {
      f(col.r);
      f(col.g);
      f(col.b);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderPainter old) => old.shader != shader;
}

/// Запасной вариант без шейдера: мягкие пятна палитры (без прожилок).
class _BlobPainter extends CustomPainter {
  final _FlameState3 state;
  _BlobPainter(Listenable frame, this.state) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    final (t, energy, c) = state();
    final w = size.width, h = size.height;
    final s = math.min(w, h * 0.75);
    final center = Offset(w / 2, h * 0.42);
    canvas.drawRect(Offset.zero & size, Paint()..color = c[3].withValues(alpha: 0.5));
    final layers = [(c[3], 0.70, 0.20, 0.0), (c[2], 0.55, 0.16, 1.7), (c[1], 0.42, 0.13, 3.1), (c[0], 0.26, 0.10, 4.6)];
    for (final (color, r, drift, seed) in layers) {
      final o = center + Offset(math.sin(t * 0.7 + seed) * s * drift, math.cos(t * 0.5 + seed * 1.3) * s * drift * 0.8);
      final rad = s * r * (1 + energy * 0.04 * math.sin(t * 6));
      canvas.drawCircle(
        o,
        rad,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0.55), color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: o, radius: rad)),
      );
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => false;
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
