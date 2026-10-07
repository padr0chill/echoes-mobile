import 'dart:convert';

import 'package:http/http.dart' as http;

import 'text_match.dart';

/// Сведения об исполнителе со Spotify — без аккаунта и ключей:
///  * страница исполнителя находится через открытую базу MusicBrainz (там хранятся ссылки на Spotify),
///    запасной путь — веб-поиск;
///  * с публичной страницы open.spotify.com (её «превью для ссылок») берутся слушатели за месяц и фото.
/// Подписчиков Spotify без входа в аккаунт не отдаёт — их показываем с SoundCloud.
class SpotifyArtist {
  final String id;
  final String? name;
  final int? monthlyListeners;
  final String? image;
  const SpotifyArtist(this.id, this.name, this.monthlyListeners, this.image);

  String get url => 'https://open.spotify.com/artist/$id';
}

class SpotifyService {
  SpotifyService._();
  static final SpotifyService instance = SpotifyService._();

  static const _mbUa = {'User-Agent': 'ECHOES-mobile/1.0 (https://github.com/padr0chill/zhopa-mobile)'};
  // «превью ссылки» — так страница отдаёт описание со слушателями и фото без JavaScript
  static const _previewUa = {'User-Agent': 'facebookexternalhit/1.1', 'Accept-Language': 'en'};
  final _cache = <String, Future<SpotifyArtist?>>{};

  Future<SpotifyArtist?> forArtist(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(key, () => _lookup(name.trim()).catchError((_) => null));
  }

  Future<SpotifyArtist?> _lookup(String name) async {
    // «Miyagi & Andy Panda» — дуэт одной строкой: не нашёлся целиком — ищем первого
    final first = name.split(RegExp(r'\s*(,|&|\bx\b|×|\bfeat\.?|\bft\.?|\bи\b)\s*', caseSensitive: false)).first.trim();
    final id = await _idFromMusicBrainz(name) ??
        (first.isNotEmpty && first != name ? await _idFromMusicBrainz(first) : null) ??
        await _idFromWeb(name);
    if (id == null) return null;
    return page(id);
  }

  /// MusicBrainz: самый похожий по имени исполнитель → его ссылка на Spotify. Сервис просит не чаще
  /// 1 запроса в секунду и иногда отвечает 503 — тогда одна повторная попытка.
  Future<String?> _idFromMusicBrainz(String name) async {
    Future<http.Response> get(Uri u) async {
      var r = await http.get(u, headers: _mbUa).timeout(const Duration(seconds: 10));
      if (r.statusCode == 503) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        r = await http.get(u, headers: _mbUa).timeout(const Duration(seconds: 10));
      }
      return r;
    }

    try {
      final s = await get(
          Uri.https('musicbrainz.org', '/ws/2/artist/', {'query': 'artist:"$name"', 'fmt': 'json', 'limit': '5'}));
      if (s.statusCode != 200) return null;
      final list = ((jsonDecode(s.body) as Map)['artists'] as List? ?? []).cast<Map>();
      // точное (с транслитерацией) совпадение имени, иначе — лучший по оценке поиска, если похож
      Map? best;
      for (final a in list) {
        final sim = TextMatch.similarity(name, '${a['name']}');
        if (sim >= 0.99) {
          best = a;
          break;
        }
        if (best == null && sim >= 0.75 && ((a['score'] ?? 0) as num) >= 90) best = a;
      }
      if (best == null) return null;
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final r =
          await get(Uri.https('musicbrainz.org', '/ws/2/artist/${best['id']}', {'inc': 'url-rels', 'fmt': 'json'}));
      if (r.statusCode != 200) return null;
      for (final rel in ((jsonDecode(r.body) as Map)['relations'] as List? ?? []).cast<Map>()) {
        final url = '${(rel['url'] as Map?)?['resource'] ?? ''}';
        final m = RegExp(r'open\.spotify\.com/artist/([A-Za-z0-9]{22})').firstMatch(url);
        if (m != null) return m.group(1);
      }
    } catch (_) {}
    return null;
  }

  /// Запасной путь: веб-поиск «имя spotify artist» → первая ссылка на страницу исполнителя.
  Future<String?> _idFromWeb(String name) async {
    try {
      final r = await http.get(Uri.https('html.duckduckgo.com', '/html/', {'q': '$name spotify artist'}), headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15'
      }).timeout(const Duration(seconds: 10));
      final m = RegExp(r'open\.spotify\.com(?:/intl-\w+)?/artist/([A-Za-z0-9]{22})').firstMatch(r.body);
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Публичная страница исполнителя: «Artist · 57.8M monthly listeners.» + фото + имя.
  Future<SpotifyArtist?> page(String id) async {
    final r = await http
        .get(Uri.https('open.spotify.com', '/artist/$id'), headers: _previewUa)
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    String? meta(String prop) =>
        RegExp('<meta[^>]+(?:property|name)="$prop"[^>]+content="([^"]*)"').firstMatch(r.body)?.group(1);
    final desc = meta('og:description') ?? meta('description') ?? '';
    final m = RegExp(r'([\d.,]+)\s*([KMB]?)\s+monthly listener', caseSensitive: false).firstMatch(desc);
    return SpotifyArtist(
        id, _unescape(meta('og:title')), m == null ? null : parseCount(m.group(1)!, m.group(2)!), meta('og:image'));
  }

  /// «57.8» + «M» → 57 800 000; «1,234» → 1234.
  static int parseCount(String num, String suffix) {
    final mul = switch (suffix.toUpperCase()) { 'K' => 1e3, 'M' => 1e6, 'B' => 1e9, _ => 1.0 };
    final n = double.tryParse(suffix.isEmpty ? num.replaceAll(',', '') : num.replaceAll(',', '.')) ?? 0;
    return (n * mul).round();
  }

  static String? _unescape(String? s) =>
      s?.replaceAll('&amp;', '&').replaceAll('&#x27;', "'").replaceAll('&#39;', "'").replaceAll('&quot;', '"');
}
