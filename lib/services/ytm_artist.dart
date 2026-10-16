import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'sc.dart';
import 'text_match.dart';
import '../i18n.dart';

/// Похожий исполнитель (лента внизу страницы).
class YtmArtistRef {
  final String id;
  final String name;
  final String? image;
  final String sub;
  const YtmArtistRef(this.id, this.name, this.image, this.sub);
}

/// Подсказка поиска «на лету»: исполнитель, песня или альбом.
class YtmSuggestion {
  final String kind; // artist, song, album
  final String id; // канал / видео / релиз
  final String title;
  final String sub;
  final String? image;
  final Track? track; // для песни
  const YtmSuggestion(this.kind, this.id, this.title, this.sub, this.image, {this.track});
}

/// Страница исполнителя YouTube Music — официальная дискография, как в Spotify.
class YtmArtistPage {
  final String id;
  final String name;
  final String? image; // большое фото для шапки
  final String? monthly; // «560 тыс. слушателей в месяц»
  final String? subscribers;
  final List<Track> top;
  final Map<String, String> plays; // id трека → «39 млн»
  final List<ScAlbum> albums;
  final List<ScAlbum> singles;
  final (String, String?)? albumsMore; // browseId, params — полный список
  final (String, String?)? singlesMore;
  final String? songsPlaylist; // «Все песни»
  final List<YtmArtistRef> similar;
  const YtmArtistPage(this.id, this.name, this.image, this.monthly, this.subscribers, this.top, this.plays, this.albums,
      this.singles, this.albumsMore, this.singlesMore, this.songsPlaylist, this.similar);
}

/// Внутренний API music.youtube.com (без ключей): исполнитель, его релизы, альбом, все песни.
class YtmBrowse {
  YtmBrowse._();
  static final YtmBrowse instance = YtmBrowse._();

  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0 Safari/537.36';
  static const _artistsOnly = 'EgWKAQIgAWoKEAkQBRAKEAMQBA==';
  final _pages = <String, (YtmArtistPage, DateTime)>{};
  final _ids = <String, String?>{};

  Future<Map> _post(String ep, Map<String, dynamic> body) async {
    final r = await http
        .post(
          Uri.parse('https://music.youtube.com/youtubei/v1/$ep?prettyPrint=false'),
          headers: {'Content-Type': 'application/json', 'Origin': 'https://music.youtube.com', 'User-Agent': _ua},
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB_REMIX',
                'clientVersion': '1.20241111.01.00',
                'hl': isEn ? 'en' : 'ru',
                'gl': 'RU'
              },
            },
            ...body,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('YouTube Music: HTTP ${r.statusCode}');
    return jsonDecode(r.body) as Map;
  }

  static String text(dynamic x) =>
      (((x as Map?)?['runs'] as List?) ?? []).map((r) => '${(r as Map)['text'] ?? ''}').join();

  static dynamic _find(dynamic x, String key) {
    if (x is Map) {
      if (x.containsKey(key)) return x[key];
      for (final v in x.values) {
        final r = _find(v, key);
        if (r != null) return r;
      }
    } else if (x is List) {
      for (final v in x) {
        final r = _find(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }

  static void _each(dynamic x, String key, void Function(Map) f) {
    if (x is Map) {
      final v = x[key];
      if (v is Map) {
        f(v);
        return;
      }
      for (final y in x.values) {
        _each(y, key, f);
      }
    } else if (x is List) {
      for (final y in x) {
        _each(y, key, f);
      }
    }
  }

  static String? _thumb(dynamic x, {int size = 544}) {
    final th = _find(x, 'thumbnails');
    if (th is! List || th.isEmpty) return null;
    final u = '${(th.last as Map)['url']}';
    return u.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w$size-h$size');
  }

  static int _secs(String s) {
    final m = RegExp(r'^(?:(\d+):)?(\d+):(\d{2})$').firstMatch(s.trim());
    if (m == null) return 0;
    return int.parse(m.group(1) ?? '0') * 3600 + int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
  }

  /// Строка списка (песня): id видео, название, исполнитель, прослушивания, длительность.
  static (Track, String?)? _row(Map it, {String? art, String? artist}) {
    final id = (it['playlistItemData'] as Map?)?['videoId'] as String?;
    if (id == null) return null;
    final cols = ((it['flexColumns'] as List?) ?? [])
        .map((c) => text(((c as Map)['musicResponsiveListItemFlexColumnRenderer'] as Map?)?['text']))
        .toList();
    if (cols.isEmpty || cols[0].isEmpty) return null;
    final fixed = ((it['fixedColumns'] as List?) ?? [])
        .map((c) => text(((c as Map)['musicResponsiveListItemFixedColumnRenderer'] as Map?)?['text']))
        .toList();
    String? plays;
    var who = cols.length > 1 ? cols[1] : '';
    for (final c in cols.skip(1)) {
      if (c.contains('прослуш') || c.contains(' plays')) plays = c.replaceAll(RegExp(r'\s*(прослушиван\S*|plays)'), '');
    }
    if (who.isEmpty || who.contains('прослуш')) who = artist ?? '';
    var secs = fixed.isEmpty ? 0 : _secs(fixed.first);
    if (secs == 0) {
      final last = cols.last.split(' • ').last;
      secs = _secs(last);
    }
    final t = Track(
        id: id,
        title: cols[0],
        artist: who.split(' • ').first.trim(),
        seconds: secs,
        art: _thumb(it['thumbnail']) ?? art);
    return (t, plays);
  }

  static ScAlbum _card(Map v, String artist) {
    final sub = text(v['subtitle']);
    final year = RegExp(r'(19|20)\d{2}').firstMatch(sub);
    final low = sub.toLowerCase();
    final kind = low.contains('сингл') || low.contains('single')
        ? 'single'
        : low.contains('ep')
            ? 'ep'
            : 'album';
    final id = ((v['navigationEndpoint'] as Map?)?['browseEndpoint'] as Map?)?['browseId'] as String?;
    return ScAlbum(0, text(v['title']), artist, null, _thumb(v['thumbnailRenderer']), 0,
        year == null ? null : int.parse(year.group(0)!), kind,
        ytm: id);
  }

  /// Канал исполнителя на YouTube Music по имени (лучшее совпадение имени).
  Future<String?> findArtist(String name) async {
    final key = name.toLowerCase().trim();
    if (_ids.containsKey(key)) return _ids[key];
    final j = await _post('search', {'query': name, 'params': _artistsOnly});
    String? best;
    var bestScore = -1.0;
    var i = 0;
    _each(j, 'musicResponsiveListItemRenderer', (it) {
      final id = ((it['navigationEndpoint'] as Map?)?['browseEndpoint'] as Map?)?['browseId'] as String?;
      if (id == null || !id.startsWith('UC')) return;
      final n =
          text(((it['flexColumns'] as List?)?.first as Map?)?['musicResponsiveListItemFlexColumnRenderer']?['text']);
      final s = TextMatch.similarity(n, name) - i * 0.05;
      i++;
      if (s > bestScore) {
        bestScore = s;
        best = id;
      }
    });
    final r = bestScore >= 0.6 ? best : null;
    _ids[key] = r;
    return r;
  }

  Future<YtmArtistPage> artist(String id) async {
    final c = _pages[id];
    if (c != null && DateTime.now().difference(c.$2) < const Duration(minutes: 30)) return c.$1;
    final j = await _post('browse', {'browseId': id});
    final h = (j['header'] as Map?)?.values.firstOrNull as Map? ?? {};
    final name = text(h['title']);
    final image = _thumb(h['thumbnail'], size: 1080);
    final monthly = text(h['monthlyListenerCount'])
        .replaceAll(RegExp(r'\s*(слушател\S*\s*в\s*месяц|monthly\s+(audience|listeners))', caseSensitive: false), '')
        .trim();
    final subs = text(_find(h['subscriptionButton'], 'subscriberCountText'));
    final top = <Track>[];
    final plays = <String, String>{};
    final albums = <ScAlbum>[], singles = <ScAlbum>[];
    (String, String?)? albumsMore, singlesMore;
    String? songs;
    final similar = <YtmArtistRef>[];
    final secs = _find(j['contents'], 'sectionListRenderer')?['contents'] as List? ?? [];
    for (final s in secs.cast<Map>()) {
      final shelf = s['musicShelfRenderer'] as Map?;
      if (shelf != null) {
        for (final it in (shelf['contents'] as List? ?? []).cast<Map>()) {
          final r = it['musicResponsiveListItemRenderer'];
          if (r is! Map) continue;
          final row = _row(r, artist: name);
          if (row == null) continue;
          top.add(row.$1);
          if (row.$2 != null) plays[row.$1.id] = row.$2!;
        }
        final be = _find(shelf['bottomEndpoint'] ?? shelf['title'], 'browseEndpoint') as Map?;
        songs = be?['browseId'] as String?;
        continue;
      }
      final car = s['musicCarouselShelfRenderer'] as Map?;
      if (car == null) continue;
      final hdr = (car['header'] as Map?)?['musicCarouselShelfBasicHeaderRenderer'] as Map?;
      final title = text(hdr?['title']).toLowerCase();
      final moreBe = _find(hdr?['moreContentButton'], 'browseEndpoint') as Map?;
      final more = moreBe == null ? null : ('${moreBe['browseId']}', moreBe['params'] as String?);
      final items =
          (car['contents'] as List? ?? []).cast<Map>().map((e) => e['musicTwoRowItemRenderer']).whereType<Map>();
      if (title.contains('альбом') || title.contains('album')) {
        albums.addAll(items.map((v) => _card(v, name)));
        albumsMore = more;
      } else if (title.contains('сингл') || title.contains('single')) {
        singles.addAll(items.map((v) => _card(v, name)));
        singlesMore = more;
      } else if (title.contains('похож') || title.contains('fans might') || title.contains('similar')) {
        for (final v in items) {
          final aid = ((v['navigationEndpoint'] as Map?)?['browseEndpoint'] as Map?)?['browseId'] as String?;
          if (aid == null) continue;
          similar
              .add(YtmArtistRef(aid, text(v['title']), _thumb(v['thumbnailRenderer'], size: 300), text(v['subtitle'])));
        }
      }
    }
    final page = YtmArtistPage(id, name, image, monthly.isEmpty ? null : monthly, subs.isEmpty ? null : subs, top,
        plays, albums, singles, albumsMore, singlesMore, songs, similar);
    _pages[id] = (page, DateTime.now());
    return page;
  }

  /// Полный список альбомов или синглов (кнопка «Ещё»).
  Future<List<ScAlbum>> discography((String, String?) more, String artist) async {
    final j = await _post('browse', {'browseId': more.$1, if (more.$2 != null) 'params': more.$2});
    final out = <ScAlbum>[];
    _each(j['contents'], 'musicTwoRowItemRenderer', (v) => out.add(_card(v, artist)));
    return out;
  }

  /// Треки альбома/сингла (+ обложка и год для шапки).
  Future<List<Track>> albumTracks(String id) async {
    final j = await _post('browse', {'browseId': id});
    final h = _find(j['contents'], 'musicResponsiveHeaderRenderer') as Map?;
    final art = _thumb(h?['thumbnail']);
    final who = text(h?['straplineTextOne']);
    final out = <Track>[];
    _each(j['contents'], 'musicResponsiveListItemRenderer', (it) {
      final r = _row(it, art: art, artist: who);
      if (r != null) out.add(r.$1);
    });
    return out;
  }

  static const _albumsOnly = 'EgWKAQIYAWoKEAkQBRAKEAMQBA==';

  /// Поиск исполнителей (фото, «… слушателей в месяц»), лучшие совпадения имени — первыми.
  Future<List<YtmArtistRef>> searchArtists(String q, {int limit = 8}) async {
    final j = await _post('search', {'query': q, 'params': _artistsOnly});
    final out = <YtmArtistRef>[];
    _each(j['contents'], 'musicResponsiveListItemRenderer', (it) {
      final id = ((it['navigationEndpoint'] as Map?)?['browseEndpoint'] as Map?)?['browseId'] as String?;
      if (id == null || !id.startsWith('UC')) return;
      final cols = ((it['flexColumns'] as List?) ?? [])
          .map((c) => text(((c as Map)['musicResponsiveListItemFlexColumnRenderer'] as Map?)?['text']))
          .toList();
      if (cols.isEmpty) return;
      final sub = cols.length > 1 ? cols[1].split(' • ').last : '';
      out.add(YtmArtistRef(id, cols[0], _thumb(it['thumbnail'], size: 300), sub));
    });
    // только похожие на запрос; точное совпадение имени — первым
    final rel =
        out.where((a) => TextMatch.similarity(a.name, q) >= 0.5 || TextMatch.similarity(q, a.name) >= 0.5).toList();
    rel.sort((a, b) => TextMatch.similarity(b.name, q).compareTo(TextMatch.similarity(a.name, q)));
    return rel.take(limit).toList();
  }

  /// Поиск альбомов: если запрос — имя исполнителя, то ЕГО дискография (альбомы, потом EP и синглы);
  /// иначе — фильтр «Альбомы» YouTube Music, только релизы, похожие на запрос. Без плейлистов SoundCloud.
  Future<List<ScAlbum>> searchAlbums(String q) async {
    int rank(ScAlbum a) => a.kind == 'album' ? 0 : (a.kind == 'ep' ? 1 : 2);
    try {
      final id = await findArtist(q);
      if (id != null) {
        final p = await artist(id);
        if (TextMatch.similarity(p.name, q) >= 0.8) {
          final albums = p.albumsMore != null ? await discography(p.albumsMore!, p.name) : p.albums;
          final singles = p.singlesMore != null ? await discography(p.singlesMore!, p.name) : p.singles;
          final all = [...albums, ...singles.where((s) => !albums.any((a) => a.ytm == s.ytm))];
          if (all.isNotEmpty) return all..sort((a, b) => rank(a).compareTo(rank(b)));
        }
      }
    } catch (_) {}
    final j = await _post('search', {'query': q, 'params': _albumsOnly});
    final out = <ScAlbum>[];
    _each(j['contents'], 'musicResponsiveListItemRenderer', (it) {
      final id = ((it['navigationEndpoint'] as Map?)?['browseEndpoint'] as Map?)?['browseId'] as String?;
      if (id == null || !id.startsWith('MPRE')) return;
      final cols = ((it['flexColumns'] as List?) ?? [])
          .map((c) => text(((c as Map)['musicResponsiveListItemFlexColumnRenderer'] as Map?)?['text']))
          .toList();
      if (cols.isEmpty) return;
      final parts = cols.length > 1 ? cols[1].split(' • ') : <String>[];
      final kindTxt = parts.isNotEmpty ? parts.first.toLowerCase() : '';
      final who = parts.length > 1 ? parts[1] : '';
      final year = RegExp(r'(19|20)\d{2}').firstMatch(cols.length > 1 ? cols[1] : '');
      out.add(ScAlbum(
          0,
          cols[0],
          who,
          null,
          _thumb(it['thumbnail']),
          0,
          year == null ? null : int.parse(year.group(0)!),
          kindTxt.contains('сингл') || kindTxt.contains('single') ? 'single' : (kindTxt == 'ep' ? 'ep' : 'album'),
          ytm: id));
    });
    final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    final rel = out.where((a) {
      final t = '${a.title} ${a.artist}'.toLowerCase();
      return words.where(t.contains).length >= (words.length / 2).ceil();
    }).toList();
    return rel..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  /// Радио YouTube Music от трека: похожие официальные треки (как «Моя волна»).
  Future<List<Track>> radio(String videoId) async {
    final j = await _post('next', {'videoId': videoId, 'playlistId': 'RDAMVM$videoId', 'isAudioOnly': true});
    final out = <Track>[];
    _each(j['contents'], 'playlistPanelVideoRenderer', (it) {
      final id = it['videoId'] as String?;
      final title = text(it['title']);
      if (id == null || title.isEmpty) return;
      final who = text(it['longBylineText']).split(' • ').first.trim();
      var art = _thumb(it['thumbnail']);
      if (art != null && art.contains('i.ytimg.com')) art = null; // превью видео — обложку соберёт SquareCover
      out.add(Track(id: id, title: title, artist: who, seconds: _secs(text(it['lengthText'])), art: art));
    });
    return out;
  }

  /// Подсказки при вводе: варианты запроса и сразу исполнители/песни/альбомы.
  Future<(List<String>, List<YtmSuggestion>)> suggest(String q) async {
    final j = await _post('music/get_search_suggestions', {'input': q});
    final queries = <String>[];
    final items = <YtmSuggestion>[];
    _each(j['contents'], 'searchSuggestionRenderer', (v) {
      final t = text(v['suggestion']);
      if (t.isNotEmpty) queries.add(t);
    });
    _each(j['contents'], 'musicResponsiveListItemRenderer', (it) {
      final cols = ((it['flexColumns'] as List?) ?? [])
          .map((c) => text(((c as Map)['musicResponsiveListItemFlexColumnRenderer'] as Map?)?['text']))
          .toList();
      if (cols.isEmpty || cols[0].isEmpty) return;
      final sub = cols.skip(1).join(' • ');
      final ne = it['navigationEndpoint'] as Map? ?? {};
      final img = _thumb(it['thumbnail'], size: 226);
      final vid = (ne['watchEndpoint'] as Map?)?['videoId'] as String?;
      final bid = (ne['browseEndpoint'] as Map?)?['browseId'] as String?;
      if (vid != null) {
        final parts = sub.split(' • ');
        final who = parts.length > 1 ? parts[1] : parts.first;
        items.add(YtmSuggestion('song', vid, cols[0], sub, img,
            track: Track(id: vid, title: cols[0], artist: who, art: img?.replaceFirst('=w226-h226', '=w544-h544'))));
      } else if (bid != null && bid.startsWith('UC')) {
        items.add(YtmSuggestion('artist', bid, cols[0], sub, img));
      } else if (bid != null && bid.startsWith('MPRE')) {
        items.add(YtmSuggestion('album', bid, cols[0], sub, img));
      }
    });
    return (queries, items);
  }

  /// «Все песни» исполнителя (плейлист VL…).
  Future<List<Track>> playlist(String id, {String? artist}) async {
    final j = await _post('browse', {'browseId': id});
    final out = <Track>[];
    _each(j['contents'], 'musicResponsiveListItemRenderer', (it) {
      final r = _row(it, artist: artist);
      if (r != null) out.add(r.$1);
    });
    return out;
  }
}
