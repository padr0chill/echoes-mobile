import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models.dart';
import 'text_match.dart';

/// Найденный клип: видео YouTube и его название.
class Clip {
  final String id;
  final String title;
  final String channel;
  final int seconds;
  const Clip(this.id, this.title, this.channel, this.seconds);
}

/// Клипы: поиск официального видео к треку и видеопоток для плеера телефона.
/// YouTube отдаёт видео целиком только как совмещённый mp4 (360p, itag 18) и только приложению — поэтому
/// плеер смотрит его через встроенный мини-прокси на 127.0.0.1 (запросы идут из приложения кусками).
class Clips {
  Clips._();
  static final Clips instance = Clips._();

  final _yt = YoutubeExplode();
  final _found = <String, Future<Clip?>>{};
  HttpServer? _server;
  final _routes = <String, Uri>{}; // путь прокси → ссылка googlevideo
  final _client = http.Client();

  /// Качество, которое удалось открыть целиком (по видео).
  final quality = <String, String>{};

  static const _audioOnly = [
    'audio',
    'lyric',
    'lyrics',
    'текст',
    'visualizer',
    'визуализ',
    'slowed',
    'sped',
    'speed up',
    'nightcore',
    'reverb',
    '8d',
    'karaoke',
    'instrumental',
    'инструментал',
    'minus',
    'cover',
    'кавер',
    'remix',
    'ремикс',
    'live',
    'концерт',
    'reaction',
    'реакция'
  ];

  /// Клип к треку: официальное видео (а не «Audio», «Lyric video», перезалив) с той же песней.
  Future<Clip?> find(Track t) => _found[t.id] ??= _find(t).catchError((_) => null);

  Future<Clip?> _find(Track t) async {
    // 1) YouTube Music, фильтр «Видео»: там официальные клипы подписаны исполнителем (а не каналом фаната)
    try {
      final c = await _findYtm(t);
      if (c != null) return c;
    } catch (_) {}
    // 2) обычный поиск YouTube
    return _findYt(t);
  }

  static const _videosOnly = 'EgWKAQIQAWoKEAkQBRAKEAMQBA==';
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0 Safari/537.36';

  static int _views(String s) {
    final m = RegExp(r'([\d.,]+)\s*(млрд|млн|тыс|B|M|K)?', caseSensitive: false).firstMatch(s);
    if (m == null) return 0;
    final n = double.tryParse(m.group(1)!.replaceAll(',', '.').replaceAll(RegExp(r'\.(?=.*\.)'), '')) ?? 0;
    final u = (m.group(2) ?? '').toLowerCase();
    return (n *
            (u == 'млрд' || u == 'b'
                ? 1e9
                : u == 'млн' || u == 'm'
                    ? 1e6
                    : u == 'тыс' || u == 'k'
                        ? 1e3
                        : 1))
        .round();
  }

  Future<Clip?> _findYtm(Track t) async {
    final r = await _client
        .post(Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false'),
            headers: {'Content-Type': 'application/json', 'Origin': 'https://music.youtube.com', 'User-Agent': _ua},
            body: jsonEncode({
              'context': {
                'client': {'clientName': 'WEB_REMIX', 'clientVersion': '1.20241111.01.00', 'hl': 'ru', 'gl': 'RU'}
              },
              'query': '${t.artist} ${t.title}',
              'params': _videosOnly,
            }))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    String text(dynamic x) => (((x as Map?)?['runs'] as List?) ?? []).map((e) => '${(e as Map)['text'] ?? ''}').join();
    Clip? best;
    var bestScore = -1e9;
    var i = 0;
    void walk(dynamic x) {
      if (x is Map) {
        final it = x['musicResponsiveListItemRenderer'];
        if (it is Map) {
          final cols = ((it['flexColumns'] as List?) ?? [])
              .map((c) => text(((c as Map)['musicResponsiveListItemFlexColumnRenderer'] as Map?)?['text']))
              .toList();
          final vid = (it['playlistItemData'] as Map?)?['videoId'] as String? ??
              RegExp(r'"videoId":"([\w-]{11})"').firstMatch(jsonEncode(it))?.group(1);
          if (vid != null && cols.length >= 2) {
            // «Название» · «Исполнитель • 1,1 млн просмотров • 2:10»
            final parts = cols[1].split(' • ');
            final who = parts.first;
            final secs = _secs(parts.last);
            final views = parts.length >= 3 ? _views(parts[1]) : 0;
            final title = cols[0];
            final low = title.toLowerCase();
            // название без имени исполнителя («Miyagi & Andy Panda - Kosandra (Official video)» → «Kosandra»)
            var bare = title.replaceAll(RegExp(RegExp.escape(who), caseSensitive: false), ' ');
            final names = t.artist.split(RegExp(r'\s*(,|&| и | x | feat\.? | ft\.? )\s*'));
            for (final w in names) {
              if (w.trim().length > 1)
                bare = bare.replaceAll(RegExp(RegExp.escape(w.trim()), caseSensitive: false), ' ');
            }
            final titleHit = TextMatch.similarity(t.title, bare);
            final inTitle = names.any((w) => w.trim().length > 1 && low.contains(w.trim().toLowerCase()));
            final artistHit = math.max(TextMatch.similarity(t.artist, who), inTitle ? 0.8 : 0.0);
            var score = titleHit * 6 + artistHit * 6 - i * 0.4;
            if (RegExp(r'official (music )?video|music video|клип|\bmv\b|official clip').hasMatch(low)) score += 4;
            // не канал исполнителя — скорее всего фанатский клип или перезалив
            final own = TextMatch.similarity(t.artist, who) >= 0.5 || TextMatch.similarity(who, t.artist) >= 0.5;
            if (!own) score -= 5;
            for (final j in _audioOnly) {
              if (low.contains(j) && !t.title.toLowerCase().contains(j)) score -= (own && j == 'audio') ? 3 : 6;
            }
            if (views > 0)
              score += math.log(views) / math.ln10 * 1.2; // популярнее (официальный) — выше // популярнее — выше
            if (t.seconds > 0 && secs > 0) score -= ((secs - t.seconds).abs() / 15).clamp(0, 4);
            if (titleHit >= 0.5 && score > bestScore) {
              bestScore = score;
              best = Clip(vid, title, who, secs);
            }
            i++;
          }
          return;
        }
        x.values.forEach(walk);
      } else if (x is List) {
        x.forEach(walk);
      }
    }

    walk(jsonDecode(r.body));
    return bestScore >= 8 ? best : null;
  }

  static int _secs(String s) {
    final m = RegExp(r'^(?:(\d+):)?(\d+):(\d{2})$').firstMatch(s.trim());
    if (m == null) return 0;
    return int.parse(m.group(1) ?? '0') * 3600 + int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
  }

  Future<Clip?> _findYt(Track t) async {
    final q = '${t.artist} ${t.title}';
    final res = await _yt.search.search('$q official video');
    final want = TextMatch.similarity;
    Clip? best;
    var bestScore = -1e9;
    var i = 0;
    for (final v in res.take(12)) {
      final d = v.duration?.inSeconds ?? 0;
      if (v.isLive || d == 0 || d > 900) continue;
      final title = v.title.toLowerCase();
      final author = v.author.toLowerCase();
      if (author.endsWith(' - topic')) continue; // «Topic» — только звук с обложкой
      final titleHit = want(t.title, v.title);
      final artistHit = want(t.artist, '${v.author} ${v.title}');
      if (titleHit < 0.5 || artistHit < 0.3) continue;
      var score = titleHit * 6 + artistHit * 4 - i * 0.3;
      if (RegExp(r'official (music )?video|music video|клип|\bmv\b|official visualizer').hasMatch(title)) score += 4;
      if (author.contains('vevo') || want(t.artist, v.author) >= 0.7) score += 2;
      for (final j in _audioOnly) {
        if (title.contains(j) && !t.title.toLowerCase().contains(j)) score -= 5;
      }
      if (t.seconds > 0) score -= ((d - t.seconds).abs() / 20).clamp(0, 4);
      if (score > bestScore) {
        bestScore = score;
        best = Clip(v.id.value, v.title, v.author, d);
      }
      i++;
    }
    return bestScore >= 7 ? best : null;
  }

  /// Адрес видео для плеера (через локальный прокси). Лучшее качество, которое YouTube отдаёт целиком.
  Future<Uri> streamUrl(String videoId) async {
    Object? last;
    for (final cl in <List<YoutubeApiClient>?>[
      [YoutubeApiClient.android],
      null,
    ]) {
      try {
        final m = cl == null
            ? await _yt.videos.streamsClient.getManifest(videoId)
            : await _yt.videos.streamsClient.getManifest(videoId, ytClients: cl);
        final muxed = m.muxed.where((s) => s.container == StreamContainer.mp4).toList()
          ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
        for (final s in muxed) {
          if (!await _tailOpen(s.url, s.size.totalBytes)) continue;
          quality[videoId] = '${s.videoResolution.height}p';
          return await _route(videoId, s.url);
        }
        last = 'YouTube не отдал видео целиком';
      } catch (e) {
        last = e;
      }
    }
    throw Exception('$last');
  }

  Future<bool> _tailOpen(Uri u, int size) async {
    if (size <= 2) return false;
    try {
      final r =
          await _client.get(u, headers: {'Range': 'bytes=${size - 2}-${size - 1}'}).timeout(const Duration(seconds: 8));
      return r.statusCode == 206 || r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Uri> _route(String id, Uri target) async {
    final s = _server ??= await _start();
    _routes['/$id.mp4'] = target;
    return Uri.parse('http://127.0.0.1:${s.port}/$id.mp4');
  }

  /// Мини-прокси: плеер просит куски (Range) у 127.0.0.1, приложение берёт их у YouTube и отдаёт дальше.
  Future<HttpServer> _start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((req) async {
      final target = _routes[req.uri.path];
      if (target == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      try {
        final up = http.Request(req.method == 'HEAD' ? 'HEAD' : 'GET', target);
        final range = req.headers.value('range');
        if (range != null) up.headers['Range'] = range;
        final r = await _client.send(up);
        req.response.statusCode = r.statusCode;
        for (final h in ['content-type', 'content-length', 'content-range', 'accept-ranges']) {
          final v = r.headers[h];
          if (v != null) req.response.headers.set(h, v);
        }
        if (r.headers['accept-ranges'] == null) req.response.headers.set('accept-ranges', 'bytes');
        await req.response.addStream(r.stream);
        await req.response.close();
      } catch (_) {
        try {
          req.response.statusCode = 502;
          await req.response.close();
        } catch (_) {}
      }
    });
    return s;
  }
}
