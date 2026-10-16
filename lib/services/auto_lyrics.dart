import 'dart:io';
import 'dart:math' as math;

import 'package:echoes_eq/echoes_eq.dart';
import 'package:flutter/foundation.dart';

import '../i18n.dart';
import '../models.dart';
import 'audio.dart';
import 'lyrics.dart';

typedef HeardWord = ({String text, double start, double dur});

/// Тест: текст и тайминги «на слух». Голос в треке распознаётся (iOS, Speech) кусками по 50 с, потом:
/// • есть текст (lrclib/свой) — распознанные слова сопоставляются со словами текста, строки получают
///   время первого совпавшего слова, остальные — между соседями;
/// • текста нет — распознанное и есть текст: слова собираются в строки по паузам.
/// Распознавание пения неидеально (музыка мешает), поэтому тайминги помечены как примерные.
class AutoLyrics {
  static bool get supported => !kIsWeb && Platform.isIOS;

  static const _chunk = 50.0;

  static Future<Lyrics> run(
    Track t,
    List<String>? lines, {
    required Duration total,
    void Function(double)? progress,
    bool Function()? cancelled,
  }) async {
    final file = await audio.audioFileFor(t);
    final secs = total.inMilliseconds / 1000;
    if (secs < 5) throw Exception(tr('неизвестна длительность трека'));
    final lang = langFor(lines, t);
    final words = <HeardWord>[];
    for (var s = 0.0; s < secs; s += _chunk) {
      if (cancelled?.call() ?? false) throw Exception(tr('отменено'));
      progress?.call(s / secs);
      words.addAll(await EchoesEq.transcribe(file.path, start: s, length: math.min(_chunk, secs - s), lang: lang));
    }
    progress?.call(1);
    if (words.where((w) => _norm(w.text).isNotEmpty).isEmpty) throw Exception(tr('голос в треке не распознан'));
    final text = lines ?? const <String>[];
    if (text.every((l) => l.trim().isEmpty)) {
      return Lyrics(group(words), true, source: 'распознано по голосу (тест)', approx: true, srcSeconds: secs.round());
    }
    return Lyrics(align(text, words, secs), true,
        source: 'синхрон по голосу (тест)', approx: true, srcSeconds: secs.round());
  }

  /// Язык распознавания: кириллица в тексте (или в названии, если текста нет) — русский, иначе английский.
  static String langFor(List<String>? lines, Track t) {
    final sample =
        (lines != null && lines.any((l) => l.trim().isNotEmpty)) ? lines.join(' ') : '${t.title} ${t.artist}';
    final cyr = RegExp(r'[а-яёА-ЯЁіїєґ]').allMatches(sample).length;
    final lat = RegExp(r'[a-zA-Z]').allMatches(sample).length;
    if (cyr > lat) return 'ru-RU';
    if (lat > cyr) return 'en-US';
    return isEn ? 'en-US' : 'ru-RU';
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  static List<String> _tokens(String line) =>
      line.split(RegExp(r'[\s\-–—]+')).map(_norm).where((w) => w.isNotEmpty).toList();

  /// Слова «одинаковые» с поправкой на ошибки распознавания: «ебашу»/«ебошу», «дождь»/«дождя».
  static bool same(String a, String b) {
    if (a == b) return true;
    final n = math.min(a.length, b.length);
    if (n < 4 || (a.length - b.length).abs() > 2) return false;
    if (a.startsWith(b) || b.startsWith(a)) return true;
    return _lev(a, b) <= (n >= 6 ? 2 : 1);
  }

  static int _lev(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + c);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// Тайминги для готового текста по распознанным словам.
  static List<LyricLine> align(List<String> lines, List<HeardWord> heard, double totalSecs) {
    // слова текста: (строка, позиция в строке, слово)
    final lyr = <(int, int, String)>[];
    for (var i = 0; i < lines.length; i++) {
      final tk = _tokens(lines[i]);
      for (var k = 0; k < tk.length; k++) {
        lyr.add((i, k, tk[k]));
      }
    }
    final rec = <(double, String)>[
      for (final w in heard)
        for (final tk in _tokens(w.text)) (w.start, tk)
    ];
    final n = lyr.length, m = rec.length;
    final anchors = <int, double>{}; // строка → время начала
    if (n > 0 && m > 0) {
      // самая длинная общая подпоследовательность слов (с «похожестью» вместо равенства)
      final dp = List.generate(n + 1, (_) => Int32List(m + 1));
      for (var i = n - 1; i >= 0; i--) {
        for (var j = m - 1; j >= 0; j--) {
          dp[i][j] = same(lyr[i].$3, rec[j].$2) ? dp[i + 1][j + 1] + 1 : math.max(dp[i + 1][j], dp[i][j + 1]);
        }
      }
      final hits = <int, List<(int, double, int)>>{}; // строка → (позиция слова, время, длина слова)
      var i = 0, j = 0;
      while (i < n && j < m) {
        if (same(lyr[i].$3, rec[j].$2) && dp[i][j] == dp[i + 1][j + 1] + 1) {
          hits.putIfAbsent(lyr[i].$1, () => []).add((lyr[i].$2, rec[j].$1, lyr[i].$3.length));
          i++;
          j++;
        } else if (dp[i + 1][j] >= dp[i][j + 1]) {
          i++;
        } else {
          j++;
        }
      }
      for (final e in hits.entries) {
        final h = e.value;
        // одно короткое совпадение («я», «и», «на») — случайность, не якорь
        if (h.length < 2 && h.first.$3 < 3) continue;
        // начало строки — от первого совпавшего слова минус ~0.3 с на каждое слово перед ним
        anchors[e.key] = math.max(0, h.first.$2 - h.first.$1 * 0.3);
      }
    }
    // якоря только по возрастанию времени
    final keys = anchors.keys.toList()..sort();
    final ok = <int, double>{};
    var last = -1.0;
    for (final k in keys) {
      if (anchors[k]! > last) {
        ok[k] = anchors[k]!;
        last = anchors[k]!;
      }
    }
    if (ok.isEmpty) return LyricsService.autoSync(lines, Duration(milliseconds: (totalSecs * 1000).round())).lines;

    // строки без якоря — по длине текста между соседними якорями
    final w = [for (final l in lines) l.trim().length + 4.0];
    final cum = <double>[0];
    for (final x in w) {
      cum.add(cum.last + x);
    }
    final idx = ok.keys.toList();
    var rate = 0.07; // с на символ — если якорь один
    if (idx.length > 1) {
      final span = ok[idx.last]! - ok[idx.first]!;
      final chars = cum[idx.last] - cum[idx.first];
      if (chars > 0) rate = (span / chars).clamp(0.03, 0.25);
    }
    final out = <LyricLine>[];
    for (var i = 0; i < lines.length; i++) {
      double at;
      if (ok.containsKey(i)) {
        at = ok[i]!;
      } else {
        final prev = idx.lastWhere((k) => k < i, orElse: () => -1);
        final next = idx.firstWhere((k) => k > i, orElse: () => -1);
        if (prev >= 0 && next >= 0) {
          final f = (cum[i] - cum[prev]) / (cum[next] - cum[prev]);
          at = ok[prev]! + (ok[next]! - ok[prev]!) * f;
        } else if (next >= 0) {
          at = ok[next]! - (cum[next] - cum[i]) * rate;
        } else {
          at = ok[prev]! + (cum[i] - cum[prev]) * rate;
        }
      }
      at = at.clamp(0, math.max(0, totalSecs - 1)).toDouble();
      out.add(LyricLine(Duration(milliseconds: (at * 1000).round()), lines[i]));
    }
    return out;
  }

  /// Текста нет — строки из распознанного: новая строка после паузы > 0,7 с или после 8 слов.
  static List<LyricLine> group(List<HeardWord> heard) {
    final out = <LyricLine>[];
    final cur = <String>[];
    double? start;
    var end = 0.0;
    void flush() {
      if (cur.isEmpty) return;
      final s = cur.join(' ');
      out.add(LyricLine(Duration(milliseconds: (start! * 1000).round()), s[0].toUpperCase() + s.substring(1)));
      cur.clear();
      start = null;
    }

    for (final w in heard) {
      final t = w.text.trim();
      if (t.isEmpty) continue;
      if (cur.isNotEmpty && (w.start - end > 0.7 || cur.length >= 8)) flush();
      start ??= w.start;
      cur.add(t);
      end = w.start + w.dur;
    }
    flush();
    return out;
  }
}
