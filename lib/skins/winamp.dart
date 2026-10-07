import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models.dart';
import '../services/audio.dart';
import '../services/store.dart';
import '../ui.dart';
import '../screens/equalizer_screen.dart';
import 'milkdrop.dart';
import '../i18n.dart';

/// Тема «Эховамп» (ECHOAMP) — как Winamp 2.x на ПК (MilkDrop — лёгкий, на видеокарте): плоские панели с фаской, чёрный ЖК
/// с зелёными цифрами, анализатор спектра, бегущая строка, серые кнопки, плейлист.
/// Без размытий и фоновых картинок — самая лёгкая тема.
class Wa {
  static const body = Color(0xFF262638);
  static const bodyDark = Color(0xFF1B1B29);
  static const hi = Color(0xFF5E5E7A); // светлая грань фаски
  static const lo = Color(0xFF0C0C12); // тёмная грань
  static const lcd = Color(0xFF000000);
  static const green = Color(0xFF00E000);
  static const greenDim = Color(0xFF0B3A0B);
  static const sel = Color(0xFF0000C6);
  static const btn = Color(0xFF3A3A50);
  static const text = Color(0xFFE6E6EE);
  static const mono = TextStyle(fontFamily: 'Menlo', fontFamilyFallback: ['Courier', 'monospace']);
}

void openMilkdrop(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MilkdropScreen()));

/// Панель с фаской: выпуклая (кнопки, рамки) или вдавленная (ЖК, плейлист).
class WaBevel extends StatelessWidget {
  final Widget child;
  final bool sunken;
  final Color color;
  final EdgeInsetsGeometry? padding;
  const WaBevel({super.key, required this.child, this.sunken = false, this.color = Wa.body, this.padding});

  @override
  Widget build(BuildContext context) {
    final a = sunken ? Wa.lo : Wa.hi, b = sunken ? Wa.hi : Wa.lo;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border(
          top: BorderSide(color: a, width: 1.5),
          left: BorderSide(color: a, width: 1.5),
          bottom: BorderSide(color: b, width: 1.5),
          right: BorderSide(color: b, width: 1.5),
        ),
      ),
      child: child,
    );
  }
}

/// Заголовок окна в духе Winamp: полоски по бокам, надпись по центру.
class WaTitleBar extends StatelessWidget {
  final String title;
  final Widget? leading;
  const WaTitleBar({super.key, required this.title, this.leading});

  @override
  Widget build(BuildContext context) {
    Widget stripes() => Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 4; i++)
              Container(
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(vertical: 1),
                  color: i.isEven ? const Color(0xFFD8D020) : Wa.hi),
          ]),
        );
    return SizedBox(
      height: context.u(30),
      child: Row(children: [
        if (leading != null) leading!,
        stripes(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(title,
              style: Wa.mono.copyWith(color: Wa.text, fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 13)),
        ),
        stripes(),
        SizedBox(width: context.u(8)),
      ]),
    );
  }
}

/// Полный плеер в теме Winamp.
class WinampPlayer extends StatelessWidget {
  const WinampPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Wa.bodyDark,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(context.u(6)),
          child: Column(children: [
            WaBevel(
              padding: EdgeInsets.all(context.u(6)),
              child: Column(children: [
                WaTitleBar(
                  title: 'ECHOAMP',
                  leading: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.keyboard_arrow_down_rounded, color: Wa.text, size: context.u(24)),
                    ),
                  ),
                ),
                SizedBox(height: context.u(4)),
                const _Display(),
                SizedBox(height: context.u(8)),
                const _WaSeek(),
                SizedBox(height: context.u(8)),
                const _Buttons(),
              ]),
            ),
            SizedBox(height: context.u(6)),
            const Expanded(child: _Playlist()),
          ]),
        ),
      ),
    );
  }
}

/// ЖК: состояние и время слева, бегущая строка и параметры справа, под временем — спектр.
class _Display extends StatelessWidget {
  const _Display();

  @override
  Widget build(BuildContext context) {
    return WaBevel(
      sunken: true,
      color: Wa.lcd,
      padding: EdgeInsets.all(context.u(8)),
      child: ValueListenableBuilder<int>(
        valueListenable: audio.trackKey,
        builder: (context, _, __) {
          final t = audio.current;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: context.u(128),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                StreamBuilder<Duration>(
                  stream: audio.player.positionStream,
                  builder: (context, snap) {
                    final p = snap.data ?? Duration.zero;
                    final mm = p.inMinutes.toString().padLeft(2, '0'),
                        ss = (p.inSeconds % 60).toString().padLeft(2, '0');
                    return Row(children: [
                      StreamBuilder<bool>(
                        stream: audio.player.playingStream,
                        builder: (context, s) => Icon(
                          (s.data ?? false) ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          color: Wa.green,
                          size: context.u(18),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('$mm:$ss',
                              style: Wa.mono
                                  .copyWith(color: Wa.green, fontSize: 28, fontWeight: FontWeight.w700, height: 1)),
                        ),
                      ),
                    ]);
                  },
                ),
                SizedBox(height: context.u(6)),
                // нажатие на спектр — MilkDrop (как щелчок по визуализации в Winamp)
                GestureDetector(
                  onTap: () => openMilkdrop(context),
                  child: SizedBox(height: context.u(34), width: double.infinity, child: const Spectrum()),
                ),
              ]),
            ),
            SizedBox(width: context.u(10)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: context.u(22),
                  child: Marquee(
                    text: t == null
                        ? 'ECHOAMP — it really whips the llama\'s ass!'
                        : '${audio.index.value + 1}. ${t.artist} - ${t.title} (${fmtDuration(t.duration)})',
                    style: Wa.mono.copyWith(color: Wa.green, fontSize: 14),
                  ),
                ),
                SizedBox(height: context.u(6)),
                Text(
                  t == null ? '' : (t.isSc ? '128 kbps  44 kHz  SoundCloud' : '128 kbps  44 kHz  YouTube'),
                  style: Wa.mono.copyWith(color: Wa.green.withValues(alpha: 0.7), fontSize: 11),
                ),
                SizedBox(height: context.u(6)),
                ValueListenableBuilder<String?>(
                  valueListenable: audio.error,
                  builder: (context, e, _) => ValueListenableBuilder<bool>(
                    valueListenable: audio.loading,
                    builder: (context, l, _) => Text(
                      e != null ? 'ERROR' : (l ? 'BUFFERING…' : 'STEREO'),
                      style: Wa.mono.copyWith(
                          color: e != null ? const Color(0xFFE03020) : Wa.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

/// Бегущая строка (как название трека в Winamp): едет, если не влезает.
class Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  const Marquee({super.key, required this.text, required this.style});

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((e) => _t.value = e.inMilliseconds / 1000.0)..start();
  final _t = ValueNotifier<double>(0);

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txt = '${widget.text}   ***   ';
    final tp = TextPainter(
      text: TextSpan(text: txt, style: widget.style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return LayoutBuilder(builder: (context, box) {
      if (tp.width / 2 < box.maxWidth * 0.95) {
        return Text(widget.text, maxLines: 1, overflow: TextOverflow.clip, style: widget.style);
      }
      return ClipRect(
        child: ValueListenableBuilder<double>(
          valueListenable: _t,
          builder: (context, t, _) {
            final dx = -((t * 40) % tp.width);
            return CustomPaint(painter: _MarqueePainter(tp, dx), size: Size(box.maxWidth, tp.height));
          },
        ),
      );
    });
  }
}

class _MarqueePainter extends CustomPainter {
  final TextPainter tp;
  final double dx;
  _MarqueePainter(this.tp, this.dx);

  @override
  void paint(Canvas canvas, Size size) {
    tp.paint(canvas, Offset(dx, 0));
    tp.paint(canvas, Offset(dx + tp.width, 0));
  }

  @override
  bool shouldRepaint(_MarqueePainter old) => old.dx != dx || old.tp != tp;
}

/// Анализатор спектра: 19 столбиков с «пиками», зелёный → жёлтый → красный. Звука плееру iOS не отдаёт,
/// поэтому столбики «танцуют» по ритму-подобному шуму, пока играет; на паузе плавно опадают.
/// 30 кадров в секунду, рисуется отдельным слоем.
class Spectrum extends StatefulWidget {
  const Spectrum({super.key});

  @override
  State<Spectrum> createState() => _SpectrumState();
}

class _SpectrumState extends State<Spectrum> with SingleTickerProviderStateMixin {
  static const n = 19;
  final _v = List<double>.filled(n, 0), _peak = List<double>.filled(n, 0);
  final _frame = ValueNotifier<int>(0);
  late final Ticker _ticker;
  final _rnd = math.Random();
  bool _playing = false;
  StreamSubscription<bool>? _sub;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sub = audio.player.playingStream.listen((p) => _playing = p);
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration now) {
    if ((now - _last).inMilliseconds < 33) return; // 30 к/с хватает
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    final t = now.inMilliseconds / 1000.0;
    final beat = math.pow(0.5 + 0.5 * math.sin(t * 2 * math.pi * 2.1), 6).toDouble(); // «бочка» ~126 BPM
    var moving = false;
    for (var i = 0; i < n; i++) {
      double target = 0;
      if (_playing) {
        final low = math.max(0.0, 1 - i / 6);
        target = (0.25 + 0.35 * _rnd.nextDouble()) * (1 - i / n * 0.55) + beat * low * 0.6;
      }
      _v[i] += (target - _v[i]) * (target > _v[i] ? 0.6 : 0.25);
      _peak[i] = math.max(_v[i], _peak[i] - dt * 0.6);
      if (_v[i] > 0.005 || _peak[i] > 0.005) moving = true;
    }
    if (moving || _playing) _frame.value++;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: CustomPaint(painter: _SpectrumPainter(_frame, _v, _peak)));
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> v, peak;
  _SpectrumPainter(Listenable frame, this.v, this.peak) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    final n = v.length;
    final w = size.width / n;
    final shader = const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Color(0xFF1B9A1B), Color(0xFF2CC82C), Color(0xFFD8D020), Color(0xFFE03020)],
      stops: [0, 0.45, 0.75, 1],
    ).createShader(Offset.zero & size);
    final bar = Paint()..shader = shader;
    final pk = Paint()..color = const Color(0xFFB0B0C0);
    for (var i = 0; i < n; i++) {
      final h = (v[i].clamp(0.0, 1.0)) * size.height;
      canvas.drawRect(Rect.fromLTWH(i * w + 0.5, size.height - h, w - 1.5, h), bar);
      final ph = peak[i].clamp(0.0, 1.0) * size.height;
      canvas.drawRect(Rect.fromLTWH(i * w + 0.5, size.height - ph - 1.5, w - 1.5, 1.5), pk);
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) => false;
}

/// Полоса перемотки: вдавленный жёлоб и выпуклый ползунок.
class _WaSeek extends StatefulWidget {
  const _WaSeek();

  @override
  State<_WaSeek> createState() => _WaSeekState();
}

class _WaSeekState extends State<_WaSeek> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audio.player.positionStream,
      builder: (context, snap) {
        final total = audio.player.duration ?? audio.current?.duration ?? Duration.zero;
        final ms = total.inMilliseconds;
        final f = _drag ?? (ms <= 0 ? 0.0 : ((snap.data ?? Duration.zero).inMilliseconds / ms).clamp(0.0, 1.0));
        return LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth, th = context.u(28);
          double at(double x) => ((x - th / 2) / (w - th)).clamp(0.0, 1.0);
          void end() {
            if (_drag != null && ms > 0) audio.seek(Duration(milliseconds: (_drag! * ms).round()));
            setState(() => _drag = null);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => setState(() => _drag = at(d.localPosition.dx)),
            onHorizontalDragUpdate: (d) => setState(() => _drag = at(d.localPosition.dx)),
            onHorizontalDragEnd: (_) => end(),
            onTapUp: (d) {
              _drag = at(d.localPosition.dx);
              end();
            },
            child: SizedBox(
              height: context.u(22),
              child: Stack(alignment: Alignment.centerLeft, children: [
                WaBevel(sunken: true, color: Wa.bodyDark, child: SizedBox(height: context.u(8), width: w)),
                Positioned(
                  left: f * (w - th),
                  child: WaBevel(
                    color: const Color(0xFF8A8AA0),
                    child: SizedBox(width: th - 3, height: context.u(14)),
                  ),
                ),
              ]),
            ),
          );
        });
      },
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons();

  @override
  Widget build(BuildContext context) {
    Widget b(IconData i, VoidCallback onTap, {String? tip}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: GestureDetector(
              onTap: onTap,
              child: WaBevel(
                color: Wa.btn,
                padding: EdgeInsets.symmetric(vertical: context.u(7)),
                child: Icon(i, color: Wa.text, size: context.u(20), semanticLabel: tip),
              ),
            ),
          ),
        );
    Widget led(String label, Listenable l, bool Function() on, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: ListenableBuilder(
            listenable: l,
            builder: (context, _) => WaBevel(
              color: Wa.btn,
              padding: EdgeInsets.symmetric(horizontal: context.u(6), vertical: context.u(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6,
                  height: 6,
                  color: on() ? Wa.green : Wa.greenDim,
                ),
                const SizedBox(width: 4),
                Text(label, style: Wa.mono.copyWith(color: Wa.text, fontSize: 10, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
    return Column(children: [
      Row(children: [
        b(Icons.skip_previous_rounded, audio.skipToPrevious, tip: tr('Назад')),
        b(Icons.play_arrow_rounded, audio.play, tip: tr('Играть')),
        b(Icons.pause_rounded, audio.pause, tip: tr('Пауза')),
        b(Icons.stop_rounded, () {
          audio.pause();
          audio.seek(Duration.zero);
        }, tip: tr('Стоп')),
        b(Icons.skip_next_rounded, audio.skipToNext, tip: tr('Дальше')),
      ]),
      SizedBox(height: context.u(6)),
      Row(children: [
        // лампочки-кнопки: не влезают в узкий экран — листаются вбок, ♥ остаётся справа
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              led('SHUFFLE', audio.shuffle, () => audio.shuffle.value, audio.toggleShuffle),
              const SizedBox(width: 4),
              led('REPEAT', audio.repeat, () => audio.repeat.value != RepeatState.off, audio.cycleRepeat),
              const SizedBox(width: 4),
              // окно эквалайзера, как в Winamp
              led('EQ', Store.instance, () => Store.instance.eqEnabled, () => openEqualizer(context)),
              const SizedBox(width: 4),
              // окно визуализации, как в Winamp
              GestureDetector(
                onTap: () => openMilkdrop(context),
                child: WaBevel(
                  color: Wa.btn,
                  padding: EdgeInsets.symmetric(horizontal: context.u(6), vertical: context.u(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome, size: 10, color: Wa.green),
                    const SizedBox(width: 4),
                    Text('MILKDROP',
                        style: Wa.mono.copyWith(color: Wa.text, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 4),
        ValueListenableBuilder<int>(
          valueListenable: audio.trackKey,
          builder: (context, _, __) => ListenableBuilder(
            listenable: Store.instance,
            builder: (context, _) {
              final t = audio.current;
              final liked = t != null && Store.instance.isLiked(t);
              return GestureDetector(
                onTap: t == null ? null : () => Store.instance.toggleLike(t),
                child: WaBevel(
                  color: Wa.btn,
                  padding: EdgeInsets.all(context.u(5)),
                  child: Icon(liked ? Icons.favorite : Icons.favorite_border,
                      size: context.u(16), color: liked ? Wa.green : Wa.text),
                ),
              );
            },
          ),
        ),
      ]),
    ]);
  }
}

/// «WINAMP PLAYLIST»: зелёный список на чёрном, текущий — белым на синей полосе.
class _Playlist extends StatelessWidget {
  const _Playlist();

  @override
  Widget build(BuildContext context) {
    return WaBevel(
      padding: EdgeInsets.all(context.u(6)),
      child: Column(children: [
        const WaTitleBar(title: 'ECHOAMP PLAYLIST'),
        SizedBox(height: context.u(4)),
        Expanded(
          child: WaBevel(
            sunken: true,
            color: Wa.lcd,
            child: ListenableBuilder(
              listenable: Listenable.merge([audio.tracks, audio.index]),
              builder: (context, _) {
                final l = audio.tracks.value, cur = audio.index.value;
                if (l.isEmpty) {
                  return Center(child: Text(tr('Плейлист пуст'), style: Wa.mono.copyWith(color: Wa.green)));
                }
                return ListView.builder(
                  itemCount: l.length,
                  itemExtent: MediaQuery.textScalerOf(context).scale(15) + context.u(10),
                  itemBuilder: (context, i) {
                    final t = l[i], on = i == cur;
                    return GestureDetector(
                      onTap: () => audio.jumpTo(i),
                      child: Container(
                        color: on ? Wa.sel : null,
                        padding: EdgeInsets.symmetric(horizontal: context.u(6)),
                        alignment: Alignment.centerLeft,
                        child: Row(children: [
                          Expanded(
                            child: Text('${i + 1}. ${t.artist} - ${t.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Wa.mono.copyWith(color: on ? Colors.white : Wa.green, fontSize: 13)),
                          ),
                          Text(t.seconds > 0 ? fmtDuration(t.duration) : '',
                              style: Wa.mono.copyWith(color: on ? Colors.white : Wa.green, fontSize: 13)),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}
