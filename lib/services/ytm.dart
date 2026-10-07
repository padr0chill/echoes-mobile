import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// YouTube Music: поиск только «песен» — официальные записи с альбомом и квадратной обложкой
/// (без клипов, «slowed», «sped up» и перезаливов). Внутренний API music.youtube.com, без ключей.
class YtmService {
  YtmService._();
  static final YtmService instance = YtmService._();

  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0 Safari/537.36';
  static const _songsOnly = 'EgWKAQIIAWoKEAkQBRAKEAMQBA==';

  Future<List<Track>> searchSongs(String q, {int limit = 25}) async {
    final r = await http
        .post(
          Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false'),
          headers: {'Content-Type': 'application/json', 'Origin': 'https://music.youtube.com', 'User-Agent': _ua},
          body: jsonEncode({
            'context': {
              'client': {'clientName': 'WEB_REMIX', 'clientVersion': '1.20241111.01.00', 'hl': 'ru', 'gl': 'RU'},
            },
            'query': q,
            'params': _songsOnly,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw Exception('YouTube Music: HTTP ${r.statusCode}');
    final out = <Track>[];
    void walk(dynamic x) {
      if (out.length >= limit) return;
      if (x is Map) {
        final it = x['musicResponsiveListItemRenderer'];
        if (it is Map) {
          final t = _parse(it);
          if (t != null) out.add(t);
          return;
        }
        x.values.forEach(walk);
      } else if (x is List) {
        x.forEach(walk);
      }
    }

    walk(jsonDecode(r.body));
    return out;
  }

  static Track? _parse(Map it) {
    final id = (it['playlistItemData'] as Map?)?['videoId'] as String?;
    if (id == null) return null;
    final cols = ((it['flexColumns'] as List?) ?? [])
        .map((c) =>
            ((((c as Map)['musicResponsiveListItemFlexColumnRenderer'] as Map?)?['text'] as Map?)?['runs'] as List? ??
                    [])
                .map((r) => '${(r as Map)['text']}')
                .join())
        .toList();
    if (cols.length < 2 || cols[0].isEmpty) return null;
    // вторая колонка: «Исполнитель • Альбом • 3:42»
    final parts = cols[1].split(' • ');
    var seconds = 0;
    final dur = RegExp(r'^(?:(\d+):)?(\d+):(\d{2})$').firstMatch(parts.last.trim());
    if (dur != null) {
      seconds = int.parse(dur.group(1) ?? '0') * 3600 + int.parse(dur.group(2)!) * 60 + int.parse(dur.group(3)!);
      parts.removeLast();
    }
    if (parts.length >= 2) parts.removeLast(); // альбом
    final artist = parts.join(' • ').trim();
    final thumbs = ((((it['thumbnail'] as Map?)?['musicThumbnailRenderer'] as Map?)?['thumbnail']
            as Map?)?['thumbnails'] as List?) ??
        [];
    String? art = thumbs.isEmpty ? null : '${(thumbs.last as Map)['url']}';
    // квадратная обложка покрупнее: …=w120-h120-… → w544-h544
    art = art?.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w544-h544');
    return Track(id: id, title: cols[0], artist: artist, seconds: seconds, art: art);
  }
}
