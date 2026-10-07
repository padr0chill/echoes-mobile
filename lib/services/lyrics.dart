import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'text_match.dart';

class LyricLine {
  final Duration at;
  final String text;
  const LyricLine(this.at, this.text);
}

class Lyrics {
  final List<LyricLine> lines; // с таймингами (synced) — at > 0; без — все нули
  final bool synced;
  final String source; // откуда: lrclib, lyrics.ovh, «свой», «синхронизировано вручную», «авто»
  final bool approx; // тайминги примерные (авто-синхронизация) — стоит подправить
  const Lyrics(this.lines, this.synced, {this.source = 'lrclib', this.approx = false});

  /// В формате LRC — так текст сохраняется на телефоне.
  String toLrc() {
    final b = StringBuffer('[re:ECHOES][src:$source]${approx ? '[approx:1]' : ''}\n');
    for (final l in lines) {
      if (synced) {
        final ms = l.at.inMilliseconds;
        b.write('[${(ms ~/ 60000).toString().padLeft(2, '0')}:'
            '${((ms % 60000) / 1000).toStringAsFixed(2).padLeft(5, '0')}]');
      }
      b.writeln(l.text);
    }
    return b.toString();
  }

  /// Сдвинуть весь текст (раньше/позже).
  Lyrics shifted(Duration d) => Lyrics(
        [for (final l in lines) LyricLine(l.at + d < Duration.zero ? Duration.zero : l.at + d, l.text)],
        synced,
        source: source,
        approx: approx,
      );
}

/// Найденный вариант текста (для выбора вручную).
class LyricsCandidate {
  final String title, artist, source;
  final int seconds;
  final String? synced, plain;
  final double score;
  const LyricsCandidate(this.title, this.artist, this.seconds, this.synced, this.plain, this.source, this.score);

  bool get hasSynced => synced != null && synced!.trim().isNotEmpty;

  Lyrics? toLyrics() {
    if (hasSynced) return Lyrics(LyricsService.parseLrc(synced!), true, source: source);
    if (plain != null && plain!.trim().isNotEmpty) {
      return Lyrics([for (final s in plain!.split('\n')) LyricLine(Duration.zero, s.trimRight())], false,
          source: source);
    }
    return null;
  }
}

/// Тексты песен: «умный» поиск по открытым базам (lrclib.net — синхронные, lyrics.ovh — запасной),
/// сверка кандидатов по названию, исполнителю и длительности; сохранённые вручную тексты и тайминги —
/// на телефоне (папка lyrics, формат LRC) и всегда в приоритете.
class LyricsService {
  LyricsService._();
  static final LyricsService instance = LyricsService._();
  final _cache = <String, Lyrics?>{};
  static const _ua = {'User-Agent': 'ECHOES mobile (https://github.com/padr0chill/zhopa-mobile)'};

  // ── сохранённые на телефоне ──

  Future<File?> _file(Track t) async {
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/lyrics');
      if (!d.existsSync()) d.createSync(recursive: true);
      return File('${d.path}/${t.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.lrc');
    } catch (_) {
      return null; // тесты / нет доступа к папке
    }
  }

  Future<Lyrics?> _loadSaved(Track t) async {
    final f = await _file(t);
    if (f == null || !f.existsSync()) return null;
    final raw = f.readAsStringSync();
    final src = RegExp(r'\[src:([^\]]*)\]').firstMatch(raw)?.group(1) ?? 'свой';
    final approx = raw.contains('[approx:1]');
    final synced = parseLrc(raw);
    if (synced.isNotEmpty) return Lyrics(synced, true, source: src, approx: approx);
    final plain = raw.split('\n').where((s) => !s.startsWith('[')).map((s) => LyricLine(Duration.zero, s)).toList();
    return plain.isEmpty ? null : Lyrics(plain, false, source: src);
  }

  /// Сохранить текст/тайминги для трека (выбранный вариант, свой текст, ручная синхронизация, сдвиг).
  Future<void> save(Track t, Lyrics l) async {
    _cache[t.id] = l;
    final f = await _file(t);
    f?.writeAsStringSync(l.toLrc());
  }

  /// Забыть сохранённое — снова искать автоматически.
  Future<void> reset(Track t) async {
    _cache.remove(t.id);
    final f = await _file(t);
    if (f != null && f.existsSync()) f.deleteSync();
  }

  Future<Lyrics?> get(Track t) async {
    if (_cache.containsKey(t.id)) return _cache[t.id];
    Lyrics? out = await _loadSaved(t);
    if (out == null) {
      try {
        final list = await search(t, quick: true);
        if (list.isNotEmpty && list.first.score >= _accept) out = list.first.toLyrics();
      } catch (_) {}
    }
    _cache[t.id] = out;
    return out;
  }

  // ── «умный» поиск ──

  static const _accept = 4.2;

  /// Все найденные варианты, лучшие сверху. query — свой запрос («исполнитель название»);
  /// quick — остановиться, как только найден уверенный вариант.
  Future<List<LyricsCandidate>> search(Track t, {String? query, bool quick = false}) async {
    final (artist, title) = cleanup(t.artist, t.title);
    final found = <String, LyricsCandidate>{};
    void add(Map<String, dynamic> j, String src) {
      final c = _candidate(j, src, artist, title, t.seconds);
      if (c == null) return;
      final key = '${c.artist}|${c.title}|${c.seconds}|${c.hasSynced}';
      final old = found[key];
      if (old == null || old.score < c.score) found[key] = c;
    }

    bool confident() => found.values.any((c) => c.score >= 5.5 && c.hasSynced);

    final queries = <Map<String, String>>[];
    if (query != null && query.trim().isNotEmpty) {
      queries.add({'q': query.trim()});
    } else {
      final tl = translit(title), al = translit(artist);
      queries.addAll([
        {'track_name': title, 'artist_name': artist},
        {'q': '$artist $title'},
        if (tl != title.toLowerCase() || al != artist.toLowerCase()) {'q': '$al $tl'},
        {'track_name': title},
        if (tl != title.toLowerCase()) {'track_name': tl},
      ]);
      // точное совпадение (с длительностью) — самый быстрый путь
      if (t.seconds > 0) {
        try {
          final r = await http
              .get(
                  Uri.https('lrclib.net', '/api/get',
                      {'artist_name': artist, 'track_name': title, 'duration': '${t.seconds}'}),
                  headers: _ua)
              .timeout(const Duration(seconds: 6));
          if (r.statusCode == 200) add(jsonDecode(r.body) as Map<String, dynamic>, 'lrclib');
        } catch (_) {}
        if (quick && confident()) return _sorted(found);
      }
    }
    for (final q in queries) {
      try {
        final r =
            await http.get(Uri.https('lrclib.net', '/api/search', q), headers: _ua).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          for (final j in (jsonDecode(r.body) as List).cast<Map<String, dynamic>>().take(20)) {
            add(j, 'lrclib');
          }
        }
      } catch (_) {}
      if (quick && confident()) break;
    }
    // запасной источник (только обычный текст)
    if (!found.values.any((c) => c.score >= _accept) && query == null) {
      try {
        final r = await http
            .get(Uri.https('api.lyrics.ovh', '/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}'))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final txt = (jsonDecode(r.body) as Map)['lyrics'] as String?;
          if (txt != null && txt.trim().isNotEmpty) {
            found['ovh'] = LyricsCandidate(title, artist, 0, null, txt.replaceAll('\r', ''), 'lyrics.ovh', _accept);
          }
        }
      } catch (_) {}
    }
    return _sorted(found);
  }

  static List<LyricsCandidate> _sorted(Map<String, LyricsCandidate> m) =>
      m.values.toList()..sort((a, b) => b.score.compareTo(a.score));

  /// Оценка совпадения: название (×3), исполнитель (×2), длительность, есть ли тайминги.
  static LyricsCandidate? _candidate(Map<String, dynamic> j, String src, String artist, String title, int seconds) {
    final synced = j['syncedLyrics'] as String?, plain = j['plainLyrics'] as String?;
    if ((synced == null || synced.trim().isEmpty) && (plain == null || plain.trim().isEmpty)) return null;
    if (j['instrumental'] == true) return null;
    final ct = '${j['trackName'] ?? j['name'] ?? ''}', ca = '${j['artistName'] ?? ''}';
    final d = ((j['duration'] ?? 0) as num).round();
    final ts = similarity(title, ct), as = similarity(artist, ca);
    var score = ts * 3 + as * 2;
    if (seconds > 0 && d > 0) {
      final dd = (d - seconds).abs();
      score += dd <= 3 ? 1.5 : (dd <= 8 ? 0.8 : (dd <= 20 ? 0 : -2));
    }
    if (synced != null && synced.trim().isNotEmpty) score += 0.5;
    if (ts < 0.5) score -= 3; // другая песня
    return LyricsCandidate(ct, ca, d, synced, plain, src, score);
  }

  // ── очистка и сравнение названий ──

  static final _junk = RegExp(
      r'\s*[\(\[][^\)\]]*(feat|ft\.|prod|official|video|audio|lyric|remaster|clip|visualizer|клип|премьера|mood|slowed|speed)[^\)\]]*[\)\]]',
      caseSensitive: false);

  /// «Исполнитель - Название (feat. X) [Official Video]» → (главный исполнитель, чистое название).
  static (String, String) cleanup(String artist, String title) {
    var a = artist.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').trim();
    var t = title.replaceAll(_junk, '').trim();
    final dash = t.indexOf(' - ');
    if (dash > 0 && dash < t.length - 3) {
      final left = t.substring(0, dash).trim();
      // в названии сам исполнитель («lil flash$ - project x») — берём правую часть
      if (a.isEmpty || similarity(a, left) >= 0.5 || a.toLowerCase().contains(left.toLowerCase())) {
        if (a.isEmpty) a = left;
        t = t.substring(dash + 3).trim();
      }
    }
    t = t.replaceAll(RegExp(r'\s+(feat\.?|ft\.?)\s+.*$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'''["«»“”]'''), '').trim();
    a = a.split(RegExp(r'\s*(,|&|\bx\b|×|\bfeat\.?|\bft\.?|\bи\b)\s*', caseSensitive: false)).first.trim();
    return (a, t);
  }

  /// Кириллица → латиница (чтобы «Мияги» и «Miyagi» сравнивались).
  static String translit(String s) => TextMatch.translit(s);

  /// 0..1: доля общих слов (с транслитерацией).
  static double similarity(String a, String b) => TextMatch.similarity(a, b);

  static List<LyricLine> parseLrc(String lrc) {
    final rx = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
    final out = <LyricLine>[];
    for (final raw in lrc.split('\n')) {
      final ms = rx.allMatches(raw).toList();
      if (ms.isEmpty) continue;
      final text = raw.replaceAll(rx, '').trim();
      for (final m in ms) {
        final mm = int.parse(m.group(1)!);
        final ss = double.parse(m.group(2)!);
        out.add(LyricLine(Duration(milliseconds: ((mm * 60 + ss) * 1000).round()), text));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  // ── авто-синхронизация ──

  /// Примерные тайминги для обычного текста: вступление и концовка — по ~8 %, строки — пропорционально
  /// числу слогов, пустые строки (между куплетами) — пауза. Потом можно подправить сдвигом или вручную.
  static Lyrics autoSync(List<String> lines, Duration total) {
    final text = [for (final l in lines) l.trimRight()];
    while (text.isNotEmpty && text.first.trim().isEmpty) {
      text.removeAt(0);
    }
    final secs = total.inMilliseconds / 1000.0;
    if (text.isEmpty || secs <= 0) return Lyrics(const [], true, source: 'авто', approx: true);
    final start = (secs * 0.08).clamp(2.0, 15.0), end = secs - (secs * 0.07).clamp(2.0, 12.0);
    int syl(String s) => RegExp(r'[aeiouyаеёиоуыэюя]', caseSensitive: false).allMatches(s).length.clamp(2, 40);
    final w = [for (final l in text) l.trim().isEmpty ? 3.0 : syl(l) + 1.0];
    final sum = w.fold<double>(0, (a, b) => a + b);
    var at = start;
    final out = <LyricLine>[];
    for (var i = 0; i < text.length; i++) {
      out.add(LyricLine(Duration(milliseconds: (at * 1000).round()), text[i].trim()));
      at += (end - start) * w[i] / sum;
    }
    return Lyrics(out, true, source: 'авто', approx: true);
  }
}
