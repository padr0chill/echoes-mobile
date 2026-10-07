import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/audio.dart';
import '../services/lyrics.dart';
import 'milkdrop_engine.dart';

/// «Слова в MilkDrop», как на ПК (milk_words): на треках с синхронным текстом слова в такт вылетают
/// ПОВЕРХ визуализации в случайных местах (сетка 3×3), крупными стильными шрифтами, у каждого своё
/// появление — pop / slam / rise / spin / glitch / stretch / fade; последнее слово строки — акцентом
/// (крупнее, другим шрифтом). Цвет — в тон текущему пресету. Картинку MilkDrop они не трогают.
class MilkdropWords extends StatefulWidget {
  final Listenable frame; // кадры MilkDrop — перерисовка в том же темпе
  final double Function() hue;
  const MilkdropWords({super.key, required this.frame, required this.hue});

  @override
  State<MilkdropWords> createState() => _MilkdropWordsState();
}

class _Word {
  final String text;
  final Duration at;
  final bool accent;
  _Word(this.text, this.at, this.accent);
}

class _Shown {
  final String text;
  final bool accent;
  final Offset pos; // доли экрана
  final int anim;
  final String font;
  final bool upper;
  final double hueShift;
  final DateTime born;
  _Shown(this.text, this.accent, this.pos, this.anim, this.font, this.upper, this.hueShift) : born = DateTime.now();
}

class _MilkdropWordsState extends State<MilkdropWords> {
  final _rnd = math.Random();
  List<_Word> _words = const [];
  String? _for;
  int _next = 0;
  Duration _lastPos = Duration.zero;
  final _shown = <_Shown>[];
  int _lastZone = -1;

  // встроенные шрифты iOS: обычные слова — «текстовые», акцент — выразительные; где нет кириллицы,
  // iOS сам подставит запасной (fontFamilyFallback)
  static const _fontsMain = [
    'Avenir Next Condensed',
    'Futura',
    'Helvetica Neue',
    'Didot',
    'American Typewriter',
    'Copperplate'
  ];
  static const _fontsAccent = [
    'Chalkduster',
    'Marker Felt',
    'Futura',
    'Snell Roundhand',
    'Noteworthy',
    'Avenir Next Condensed'
  ];

  @override
  void initState() {
    super.initState();
    audio.trackKey.addListener(_load);
    widget.frame.addListener(_tick);
    _load();
  }

  @override
  void dispose() {
    audio.trackKey.removeListener(_load);
    widget.frame.removeListener(_tick);
    super.dispose();
  }

  void _load() {
    final t = audio.current;
    if (t == null || t.id == _for) return;
    _for = t.id;
    _words = const [];
    _shown.clear();
    _next = 0;
    LyricsService.instance.get(t).then((ly) {
      if (!mounted || audio.current?.id != t.id || ly == null || !ly.synced) return;
      _words = _split(ly.lines);
      _next = 0;
    });
  }

  /// Строки → слова со своим временем: строка делится между словами пропорционально их длине
  /// (не дольше 4 с на строку — дальше обычно проигрыш).
  static List<_Word> _split(List<LyricLine> lines) {
    final out = <_Word>[];
    for (var i = 0; i < lines.length; i++) {
      final words = lines[i].text.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty).toList();
      if (words.isEmpty) continue;
      final start = lines[i].at;
      final end = i + 1 < lines.length ? lines[i + 1].at : start + const Duration(seconds: 3);
      var span = (end - start).inMilliseconds.clamp(300, 4000);
      final total = words.fold<int>(0, (s, w) => s + w.length + 2);
      var t = 0.0;
      for (var k = 0; k < words.length; k++) {
        out.add(_Word(words[k], start + Duration(milliseconds: t.round()), k == words.length - 1));
        t += span * (words[k].length + 2) / total * 0.85;
      }
    }
    return out;
  }

  void _tick() {
    if (_words.isEmpty) {
      if (_shown.isNotEmpty) setState(_shown.clear);
      return;
    }
    final pos = audio.player.position + const Duration(milliseconds: 120);
    // перемотали назад/вперёд — продолжить с нужного места, без «залпа» пропущенных слов
    if (pos < _lastPos - const Duration(seconds: 1) || pos > _lastPos + const Duration(seconds: 3)) {
      _next = _words.indexWhere((w) => w.at >= pos);
      if (_next < 0) _next = _words.length;
    }
    _lastPos = pos;
    var changed = false;
    while (_next < _words.length && _words[_next].at <= pos) {
      _spawn(_words[_next]);
      _next++;
      changed = true;
    }
    final now = DateTime.now();
    final before = _shown.length;
    _shown.removeWhere((s) => now.difference(s.born).inMilliseconds > (s.accent ? 1700 : 1250));
    if (changed || before != _shown.length || _shown.isNotEmpty) setState(() {});
  }

  void _spawn(_Word w) {
    // зона 3×3, не та же, что у прошлого слова
    var z = _rnd.nextInt(9);
    if (z == _lastZone) z = (z + 1 + _rnd.nextInt(8)) % 9;
    _lastZone = z;
    final pos = Offset(
      (z % 3) / 3 + 1 / 6 + (_rnd.nextDouble() - 0.5) * 0.12,
      (z ~/ 3) / 3 + 1 / 6 + (_rnd.nextDouble() - 0.5) * 0.10,
    );
    final fonts = w.accent ? _fontsAccent : _fontsMain;
    _shown.add(_Shown(w.text, w.accent, pos, _rnd.nextInt(7), fonts[_rnd.nextInt(fonts.length)],
        w.accent || _rnd.nextDouble() < 0.35, _rnd.nextDouble() * 0.3));
    if (_shown.length > 7) _shown.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    if (_shown.isEmpty) return const SizedBox.expand();
    return IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: _WordsPainter(List.of(_shown), widget.hue())));
  }
}

class _WordsPainter extends CustomPainter {
  final List<_Shown> words;
  final double hue;
  _WordsPainter(this.words, this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final base = math.min(size.width, size.height);
    for (final w in words) {
      final life = w.accent ? 1700.0 : 1250.0;
      final t = (now.difference(w.born).inMilliseconds / life).clamp(0.0, 1.0);
      // появление (первые 18 %) и угасание (последние 30 %)
      final inK = Curves.easeOutBack.transform((t / 0.18).clamp(0.0, 1.0));
      final outK = t < 0.7 ? 1.0 : 1 - Curves.easeIn.transform((t - 0.7) / 0.3);
      final alpha = (math.min(1.0, t / 0.08) * outK).clamp(0.0, 1.0);
      if (alpha <= 0.01) continue;
      final color = MdWaveDrawer.hsv(hue + 0.5 + w.hueShift, w.accent ? 0.25 : 0.45, 1);
      final fontSize = base * (w.accent ? 0.13 : 0.085);
      final tp = TextPainter(
        text: TextSpan(
          text: w.upper ? w.text.toUpperCase() : w.text,
          style: TextStyle(
            fontFamily: w.font,
            fontFamilyFallback: const ['Helvetica Neue', 'Arial'],
            fontSize: fontSize,
            fontWeight: w.accent ? FontWeight.w900 : FontWeight.w700,
            color: color.withValues(alpha: alpha),
            letterSpacing: w.accent ? 1.5 : 0.5,
            shadows: [
              Shadow(color: color.withValues(alpha: 0.55 * alpha), blurRadius: fontSize * 0.45),
              Shadow(color: Colors.black.withValues(alpha: 0.6 * alpha), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width * 0.9);
      var cx = w.pos.dx * size.width, cy = w.pos.dy * size.height;
      cx = cx.clamp(tp.width / 2 + 8, size.width - tp.width / 2 - 8);
      canvas.save();
      canvas.translate(cx, cy);
      switch (w.anim) {
        case 0: // pop
          canvas.scale(0.4 + 0.6 * inK);
        case 1: // slam — из большого
          final k = 1 + 1.4 * (1 - inK);
          canvas.scale(k);
        case 2: // rise — снизу
          canvas.translate(0, (1 - inK) * base * 0.12);
        case 3: // spin
          canvas.rotate((1 - inK) * -0.6);
          canvas.scale(0.6 + 0.4 * inK);
        case 4: // glitch — подёргивание с цветным «расслоением»
          final j = t < 0.35 ? (math.sin(t * 140) * base * 0.012) : 0.0;
          canvas.translate(j, 0);
          if (t < 0.35) {
            final ghost = TextPainter(
              text: TextSpan(
                text: w.upper ? w.text.toUpperCase() : w.text,
                style: TextStyle(
                  fontFamily: w.font,
                  fontFamilyFallback: const ['Helvetica Neue', 'Arial'],
                  fontSize: fontSize,
                  fontWeight: w.accent ? FontWeight.w900 : FontWeight.w700,
                  color: const Color(0xFFFF2D6A).withValues(alpha: 0.5 * alpha),
                ),
              ),
              textDirection: TextDirection.ltr,
              maxLines: 1,
            )..layout(maxWidth: size.width * 0.9);
            ghost.paint(canvas, Offset(-tp.width / 2 + base * 0.008, -tp.height / 2));
          }
        case 5: // stretch — растянуто по ширине и сжимается
          canvas.scale(1 + 1.2 * (1 - inK), 1);
        default: // fade — просто проявляется
          break;
      }
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WordsPainter old) => true;
}
