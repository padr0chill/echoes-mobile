import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class LyricLine {
  final Duration at;
  final String text;
  const LyricLine(this.at, this.text);
}

class Lyrics {
  final List<LyricLine> lines; // с таймингами (synced) — at > 0; без — все нули
  final bool synced;
  const Lyrics(this.lines, this.synced);
}

/// Тексты песен из открытой базы lrclib.net (синхронные, если есть).
class LyricsService {
  LyricsService._();
  static final LyricsService instance = LyricsService._();
  final _cache = <String, Lyrics?>{};

  Future<Lyrics?> get(Track t) async {
    if (_cache.containsKey(t.id)) return _cache[t.id];
    Lyrics? out;
    try {
      final q = Uri.https('lrclib.net', '/api/search', {'q': '${t.artist} ${t.title}'});
      final r = await http.get(q, headers: {'User-Agent': 'ECHOES mobile (test)'}).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
        Map<String, dynamic>? best;
        // ближайший по длительности, синхронный в приоритете
        list.sort((a, b) {
          final da = ((a['duration'] ?? 0) as num).toDouble() - t.seconds;
          final db = ((b['duration'] ?? 0) as num).toDouble() - t.seconds;
          final sa = a['syncedLyrics'] != null ? 0 : 1;
          final sb = b['syncedLyrics'] != null ? 0 : 1;
          return sa != sb ? sa - sb : da.abs().compareTo(db.abs());
        });
        if (list.isNotEmpty) best = list.first;
        if (best != null) {
          final synced = best['syncedLyrics'] as String?;
          final plain = best['plainLyrics'] as String?;
          if (synced != null && synced.trim().isNotEmpty) {
            out = Lyrics(_parseLrc(synced), true);
          } else if (plain != null && plain.trim().isNotEmpty) {
            out = Lyrics(plain.split('\n').map((s) => LyricLine(Duration.zero, s)).toList(), false);
          }
        }
      }
    } catch (_) {
      out = null;
    }
    _cache[t.id] = out;
    return out;
  }

  static List<LyricLine> _parseLrc(String lrc) {
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
}
