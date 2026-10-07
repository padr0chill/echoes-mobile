import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'services/audio.dart';
import 'services/lyrics.dart';
import 'ui.dart';
import 'widgets.dart';

/// Виниловая пластинка вместо обложки: обложка — «яблоко» в центре, бороздки, блик.
/// Крутится, пока играет (33⅓ об/мин), плавно разгоняется и останавливается. Крутится только слой с
/// пластинкой (готовая картинка + поворот) — сам диск не перерисовывается, блик стоит на месте.
class VinylDisc extends StatefulWidget {
  final Track? track;
  final double size;
  const VinylDisc({super.key, required this.track, required this.size});

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  final _angle = ValueNotifier<double>(0);
  double _speed = 0; // оборотов в секунду (плавно → 0,555)
  Duration _last = Duration.zero;
  bool _playing = false;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = audio.player.playingStream.listen((p) {
      _playing = p;
      if (p && !_spin.isAnimating) _spin.repeat();
    });
    _spin.addListener(_tick);
  }

  void _tick() {
    final now = _spin.lastElapsedDuration ?? Duration.zero;
    var dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt < 0 || dt > 0.1) dt = 0.016;
    final target = _playing ? 0.555 : 0.0;
    _speed += (target - _speed) * (1 - math.exp(-dt * 3));
    _angle.value = (_angle.value + _speed * dt * 2 * math.pi) % (2 * math.pi);
    if (!_playing && _speed < 0.002) {
      _speed = 0;
      _spin.stop();
      _last = Duration.zero;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spin.dispose();
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final disc = RepaintBoundary(
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(alignment: Alignment.center, children: [
          const Positioned.fill(child: CustomPaint(painter: _GroovesPainter())),
          ClipOval(child: Cover(track: widget.track, size: s * 0.36, radius: 0, big: true)),
          // отверстие
          Container(
            width: s * 0.03,
            height: s * 0.03,
            decoration: const BoxDecoration(color: Color(0xFF0A0A0A), shape: BoxShape.circle),
          ),
        ]),
      ),
    );
    return SizedBox(
      width: s,
      height: s,
      child: Stack(children: [
        // тень под пластинкой
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55), blurRadius: s * 0.08, offset: Offset(0, s * 0.03))
              ],
            ),
          ),
        ),
        ValueListenableBuilder<double>(
          valueListenable: _angle,
          builder: (context, a, child) => Transform.rotate(angle: a, child: child),
          child: disc,
        ),
        // блик — неподвижный (свет падает с одной стороны, пластинка крутится под ним)
        const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _SheenPainter()))),
      ]),
    );
  }
}

class _GroovesPainter extends CustomPainter {
  const _GroovesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
            colors: [Color(0xFF1C1C1E), Color(0xFF0B0B0C), Color(0xFF151517)],
            stops: [0.3, 0.8, 1]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // бороздки: тонкие кольца разной яркости; «дорожки» между треками — чуть шире
    final p = Paint()..style = PaintingStyle.stroke;
    final rnd = math.Random(7);
    for (var rr = r * 0.97; rr > r * 0.21; rr -= r * 0.0105) {
      p
        ..strokeWidth = r * 0.004
        ..color = Colors.white.withValues(alpha: 0.025 + rnd.nextDouble() * 0.04);
      canvas.drawCircle(c, rr, p);
    }
    for (final k in [0.52, 0.68, 0.84]) {
      p
        ..strokeWidth = r * 0.012
        ..color = Colors.black.withValues(alpha: 0.6);
      canvas.drawCircle(c, r * k, p);
    }
    // ободок
    p
      ..strokeWidth = r * 0.015
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawCircle(c, r * 0.99, p);
  }

  @override
  bool shouldRepaint(_GroovesPainter old) => false;
}

class _SheenPainter extends CustomPainter {
  const _SheenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    // блик — только на виниле: кольцо без «яблока» в центре (обрезка чётно-нечётным контуром)
    canvas.clipPath(Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(rect)
      ..addOval(Rect.fromCircle(center: c, radius: r * 0.19)));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.13),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.05, 0.13, 0.22, 0.55, 0.63, 0.72],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SheenPainter old) => false;
}

/// Строка текста песни под пластинкой: текущая — крупно, следующая — бледнее; смена — плавно.
/// Нет синхронного текста — тихо ничего не показывает.
class LyricsTicker extends StatefulWidget {
  final Track track;
  const LyricsTicker({super.key, required this.track});

  /// Высота блока: текущая строка — до 3 строк, следующая — до 2 (с учётом размера шрифта).
  static double heightFor(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(20 * 1.2 * 3 + 4 + 15 * 1.3 * 2) + context.u(8);

  @override
  State<LyricsTicker> createState() => _LyricsTickerState();
}

class _LyricsTickerState extends State<LyricsTicker> {
  // (высота блока — LyricsTicker.heightFor: 3 строки текущей + 2 следующей)
  Lyrics? _ly;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LyricsTicker old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track) {
      _ly = null;
      _load();
    }
  }

  Future<void> _load() async {
    final t = widget.track;
    final ly = await LyricsService.instance.get(t);
    if (mounted && widget.track == t) setState(() => _ly = ly);
  }

  @override
  Widget build(BuildContext context) {
    final ly = _ly;
    final h = LyricsTicker.heightFor(context);
    if (ly == null || !ly.synced || ly.lines.isEmpty) return SizedBox(height: h);
    return SizedBox(
      height: h,
      child: StreamBuilder<Duration>(
        stream: audio.player.positionStream,
        builder: (context, snap) {
          final pos = (snap.data ?? Duration.zero) + const Duration(milliseconds: 250);
          var cur = -1;
          for (var i = 0; i < ly.lines.length; i++) {
            if (ly.lines[i].at <= pos) cur = i;
          }
          String line(int i) =>
              i >= 0 && i < ly.lines.length ? (ly.lines[i].text.isEmpty ? '♪' : ly.lines[i].text) : '';
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                child: c,
              ),
            ),
            child: Column(
              key: ValueKey(cur),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // строка целиком: переносится до 3 строк (а не обрезается «…»)
                Text(line(cur),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 4),
                Text(line(cur + 1),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45), fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          );
        },
      ),
    );
  }
}
