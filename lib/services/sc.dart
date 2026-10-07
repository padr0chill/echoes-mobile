import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Трек SoundCloud: подходит ли (полный, не 30-секундный отрывок) и откуда брать звук.
class ScTrack {
  final int id;
  final String title;
  final String artist;
  final int seconds;
  final bool snippet; // только отрывок (Go+)
  final List<Map<String, dynamic>> transcodings;
  final String? auth;
  final String? art;

  ScTrack(this.id, this.title, this.artist, this.seconds, this.snippet, this.transcodings, this.auth, this.art);

  bool get playable => !snippet && transcodings.any((t) => !_isOpus(t));

  Track toTrack() => Track(id: 'sc:$id', title: title, artist: artist, seconds: seconds, art: art);
}

bool _isOpus(Map t) {
  final mime = '${(t['format'] as Map?)?['mime_type'] ?? ''}';
  return mime.contains('opus') || mime.contains('ogg');
}

/// SoundCloud: поиск, «похожие треки» (для волны и рекомендаций) и запасной источник звука для YouTube.
/// client_id — как у yt-dlp: из JS-бандлов soundcloud.com (публичного ключа SoundCloud не даёт).
class ScService {
  ScService._();
  static final ScService instance = ScService._();

  // настольный браузер: мобильная версия сайта собрана иначе, и client_id в ней не найти
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0 Safari/537.36';
  String? _clientId;
  final _byId = <int, ScTrack>{};

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

  /// GET api-v2 с client_id; устаревший ключ (401/403) — один раз взять новый.
  Future<dynamic> _api(String path, [Map<String, String> q = const {}]) async {
    for (final fresh in [false, true]) {
      final cid = await clientId(fresh: fresh);
      final r = await http
          .get(Uri.https('api-v2.soundcloud.com', path, {...q, 'client_id': cid}), headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 401 || r.statusCode == 403) continue;
      if (r.statusCode != 200) throw Exception('SoundCloud: HTTP ${r.statusCode}');
      return jsonDecode(r.body);
    }
    throw Exception('SoundCloud: ключ не принят');
  }

  ScTrack _parse(Map t) {
    String? art = (t['artwork_url'] ?? (t['user'] as Map?)?['avatar_url']) as String?;
    art = art?.replaceAll('-large.', '-t500x500.');
    final full = ((t['full_duration'] ?? t['duration'] ?? 0) as num).toInt();
    final dur = ((t['duration'] ?? 0) as num).toInt();
    final s = ScTrack(
      (t['id'] as num).toInt(),
      '${t['title'] ?? ''}',
      '${(t['user'] as Map?)?['username'] ?? ''}',
      (full / 1000).round(),
      t['policy'] == 'SNIP' || (dur < 31000 && full > 40000),
      (((t['media'] as Map?)?['transcodings'] as List?) ?? []).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      t['track_authorization'] as String?,
      art,
    );
    _byId[s.id] = s;
    return s;
  }

  Future<List<ScTrack>> search(String q, {int limit = 20}) async {
    final j = await _api('/search/tracks', {'q': q, 'limit': '$limit'});
    return ((j as Map)['collection'] as List? ?? []).cast<Map>().map(_parse).toList();
  }

  /// Поиск для экрана: только полные треки, которые можно включить.
  Future<List<Track>> searchTracks(String q, {int limit = 25}) async =>
      (await search(q, limit: limit)).where((t) => t.playable).map((t) => t.toTrack()).toList();

  /// «Похожие» на трек SoundCloud — для волны и рекомендаций.
  Future<List<Track>> related(int id, {int limit = 30}) async {
    final j = await _api('/tracks/$id/related', {'limit': '$limit'});
    return ((j as Map)['collection'] as List? ?? [])
        .cast<Map>()
        .map(_parse)
        .where((t) => t.playable)
        .map((t) => t.toTrack())
        .toList();
  }

  Future<ScTrack> track(int id) async {
    final c = _byId[id];
    if (c != null && c.transcodings.isNotEmpty) return c;
    return _parse(await _api('/tracks/$id') as Map);
  }

  /// Ссылка на звук: обычный mp3 (progressive), иначе HLS — оба iPhone играет сам.
  Future<Uri> streamUrl(ScTrack t) async {
    final cid = await clientId();
    final list = t.transcodings.where((x) => !_isOpus(x)).toList()
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

  static const _junk = [
    'cover', 'flip', 'remix', 'mashup', 'edit', 'sped up', 'speed up', 'slowed', 'nightcore', 'remake',
    '8d', 'bass boosted', 'live', 'karaoke', 'instrumental', 'reverb', 'кавер', 'ремикс', 'минус', 'перепев',
  ];

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ').replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

  /// Та же песня на SoundCloud: слова названия совпадают, длительность близка (±15 с или ±8 %), не отрывок.
  /// Два запроса: «исполнитель название», затем только название.
  /// strict — для замены звука: ремиксы, каверы и т. п. не годятся (это другая песня);
  /// не строго — для поиска «похожих» в волне (ремикс как отправная точка не мешает).
  Future<ScTrack?> match(String artist, String title, int seconds, {bool strict = true}) async {
    final want = _norm(title).split(' ').where((w) => w.length > 1).toSet();
    final wantText = '$artist $title'.toLowerCase(); // со скобками: «(Remix)» и т. п. важны
    final artistWords = _norm(artist).split(' ').where((w) => w.length > 1).toSet();
    final tol = seconds > 0 ? (seconds * 0.08).clamp(15, 40) : 1 << 30;
    ScTrack? best;
    var bestScore = -1e9;
    final seen = <int>{};
    for (final q in {'$artist $title', _norm(title)}) {
      if (q.trim().isEmpty) continue;
      List<ScTrack> res;
      try {
        res = await search(q, limit: 20);
      } catch (_) {
        continue;
      }
      for (final t in res) {
        if (!seen.add(t.id) || !t.playable) continue;
        final text = _norm('${t.artist} ${t.title}');
        final words = text.split(' ').toSet();
        final hit = want.isEmpty ? 1.0 : want.where(words.contains).length / want.length;
        if (hit < 0.6) continue;
        final dd = seconds > 0 ? (t.seconds - seconds).abs() : 0;
        if (dd > tol) continue;
        final artistHit = artistWords.isEmpty ? 1.0 : artistWords.where(words.contains).length / artistWords.length;
        if (artistHit == 0) continue; // тот же заголовок у другого исполнителя — скорее всего другая песня
        // каверы, ремиксы, ускоренные и т. п. — только если их просили
        var junk = 0;
        final raw = '${t.artist} ${t.title}'.toLowerCase();
        for (final j in _junk) {
          if (raw.contains(j) && !wantText.contains(j)) junk++;
        }
        if (strict && junk > 0) continue;
        final own = artistWords.isNotEmpty && artistWords.every(_norm(t.artist).split(' ').contains) ? 3 : 0;
        final score = hit * 10 + artistHit * 6 + own - junk * 9 - dd / 4;
        if (score > bestScore) {
          bestScore = score;
          best = t;
        }
      }
      if (best != null && bestScore > 12) break; // уверенно нашли — второй запрос не нужен
    }
    return best;
  }

  /// Ссылка на ту же песню (запасной источник для YouTube) или null.
  Future<Uri?> findSame(String artist, String title, int seconds) async {
    final t = await match(artist, title, seconds);
    return t == null ? null : streamUrl(t);
  }
}
