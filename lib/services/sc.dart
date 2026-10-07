import 'dart:convert';

import 'package:http/http.dart' as http;

/// Трек SoundCloud: подходит ли как замена (полный, не 30-секундный отрывок) и откуда брать звук.
class ScTrack {
  final int id;
  final String title;
  final String artist;
  final int seconds;
  final bool snippet; // только отрывок (Go+)
  final List<Map<String, dynamic>> transcodings;
  final String? auth;

  ScTrack(this.id, this.title, this.artist, this.seconds, this.snippet, this.transcodings, this.auth);
}

/// SoundCloud как запасной источник звука: если YouTube не отдал поток, та же песня ищется здесь.
/// client_id — как у yt-dlp: из JS-бандлов soundcloud.com (публичного ключа SoundCloud не даёт).
class ScService {
  ScService._();
  static final ScService instance = ScService._();

  // настольный браузер: мобильная версия сайта собрана иначе, и client_id в ней не найти
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0 Safari/537.36';
  String? _clientId;

  Future<String> clientId({bool fresh = false}) async {
    if (_clientId != null && !fresh) return _clientId!;
    final home = await http.get(Uri.https('soundcloud.com', '/'), headers: {'User-Agent': _ua}).timeout(
          const Duration(seconds: 12),
        );
    final scripts = RegExp(r'<script[^>]+src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"')
        .allMatches(home.body)
        .map((m) => m.group(1)!)
        .toList()
        .reversed;
    for (final src in scripts) {
      try {
        final js = await http.get(Uri.parse(src), headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 12));
        final m = RegExp(r'client_id\s*:\s*"([0-9a-zA-Z]{32})"').firstMatch(js.body);
        if (m != null) return _clientId = m.group(1)!;
      } catch (_) {}
    }
    throw Exception('SoundCloud: не найден client_id');
  }

  Future<List<ScTrack>> search(String q) async {
    for (final fresh in [false, true]) {
      final cid = await clientId(fresh: fresh);
      final r = await http.get(
        Uri.https('api-v2.soundcloud.com', '/search/tracks', {'q': q, 'client_id': cid, 'limit': '12'}),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 401 || r.statusCode == 403) continue; // ключ устарел — взять новый
      if (r.statusCode != 200) throw Exception('SoundCloud: HTTP ${r.statusCode}');
      final col = ((jsonDecode(r.body) as Map)['collection'] as List? ?? []).cast<Map>();
      return [
        for (final t in col)
          ScTrack(
            (t['id'] as num).toInt(),
            '${t['title'] ?? ''}',
            '${(t['user'] as Map?)?['username'] ?? ''}',
            (((t['full_duration'] ?? t['duration'] ?? 0) as num) / 1000).round(),
            t['policy'] == 'SNIP' || (((t['duration'] ?? 0) as num) < 31000 && ((t['full_duration'] ?? 0) as num) > 40000),
            (((t['media'] as Map?)?['transcodings'] as List?) ?? []).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
            t['track_authorization'] as String?,
          ),
      ];
    }
    throw Exception('SoundCloud: ключ не принят');
  }

  /// Ссылка на звук: обычный mp3 (progressive), иначе HLS — оба iPhone играет сам.
  Future<Uri> streamUrl(ScTrack t) async {
    final cid = await clientId();
    final list = List.of(t.transcodings)
      ..sort((a, b) {
        int rank(Map x) {
          final f = (x['format'] as Map?) ?? {};
          final prog = f['protocol'] == 'progressive' ? 0 : 1;
          final mime = '${f['mime_type'] ?? ''}';
          final codec = mime.contains('mpeg') ? 0 : mime.contains('mp4') ? 1 : 2;
          return prog * 10 + codec;
        }

        return rank(a).compareTo(rank(b));
      });
    for (final tc in list) {
      final f = (tc['format'] as Map?) ?? {};
      if ('${f['mime_type']}'.contains('opus') || '${f['mime_type']}'.contains('ogg')) continue; // iOS не играет
      final base = Uri.parse('${tc['url']}');
      final u = base.replace(queryParameters: {
        ...base.queryParameters,
        'client_id': cid,
        if (t.auth != null) 'track_authorization': t.auth!,
      });
      try {
        final r = await http.get(u, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) continue;
        final url = (jsonDecode(r.body) as Map)['url'] as String?;
        if (url != null) return Uri.parse(url);
      } catch (_) {}
    }
    throw Exception('SoundCloud: нет доступного потока');
  }

  /// Та же песня: совпадение слов названия и длительность ±12 с, не отрывок.
  Future<Uri?> findSame(String artist, String title, int seconds) async {
    final res = await search('$artist $title');
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
    final want = norm(title).split(' ').where((w) => w.length > 1).toSet();
    ScTrack? best;
    var bestScore = -1.0;
    for (final t in res) {
      if (t.snippet || t.transcodings.isEmpty) continue;
      final words = norm('${t.artist} ${t.title}').split(' ').toSet();
      final hit = want.isEmpty ? 1.0 : want.where(words.contains).length / want.length;
      if (hit < 0.5) continue;
      final dd = seconds > 0 ? (t.seconds - seconds).abs() : 0;
      if (seconds > 0 && dd > 12) continue;
      final score = hit * 10 - dd / 5;
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best == null ? null : streamUrl(best);
  }
}
