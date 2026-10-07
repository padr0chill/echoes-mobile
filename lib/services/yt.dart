import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models.dart';
import 'ytm.dart';
import '../i18n.dart';

/// Выбранный аудиопоток: ссылка, размер (для перемотки через прокси), тип и каким клиентом получен.
class StreamPick {
  final Uri url;
  final int size;
  final String mime;
  final int client; // индекс в YtService.clients — следующий запасной начинается с client + 1

  const StreamPick(this.url, this.size, this.mime, this.client);
}

/// Поиск и аудиопоток YouTube прямо на телефоне. Ничего не скачивается: плееру отдаётся поток,
/// он берёт звук небольшими кусками по мере прослушивания.
class YtService {
  YtService._();
  static final YtService instance = YtService._();

  final _yt = YoutubeExplode();
  final _cache = <String, (StreamPick, DateTime)>{};

  /// Способы получить поток, по порядку. Проверено 06.10.2026: рабочие ссылки (HTTP 206) стабильно даёт
  /// только клиент «android»; «по умолчанию» — то да, то 403; ios/mweb — 403, androidVr/tv — «недоступно».
  /// YouTube это периодически меняет — проверка: dart run tool/probe_clients.dart
  static final clients = <List<YoutubeApiClient>?>[
    [YoutubeApiClient.android],
    null,
    [YoutubeApiClient.ios],
    [YoutubeApiClient.androidVr],
    [YoutubeApiClient.tv],
  ];

  Future<List<Track>> search(String query) async {
    final res = await _yt.search.search(query);
    final out = <Track>[];
    for (final v in res) {
      final d = v.duration;
      if (v.isLive || d == null || d == Duration.zero || d.inMinutes >= 25) continue;
      out.add(trackFromVideo(v.id.value, v.title, v.author, d));
    }
    return out;
  }

  /// Аудиопоток AAC (mp4) — его играет iOS; «экономия» — самый лёгкий. from — с какого способа начинать.
  final _ytIds = <String, String>{};
  static const _junk = [
    'live',
    'remix',
    'cover',
    'extended',
    'reanimation',
    'karaoke',
    'sped up',
    'slowed',
    'nightcore',
    'instrumental',
    'кавер',
    'ремикс'
  ];

  /// Видео YouTube с той же песней: слова названия, исполнитель и близкая длительность.
  /// Видео с той же песней: сначала среди официальных песен YouTube Music, затем обычный поиск YouTube.
  /// Сравниваются слова названия, исполнитель и длительность; концертные, ремиксы и т. п. — штраф.
  /// exclude — видео, которое не открылось: ищем ту же песню другим видео (без кэша).
  Future<String> findSame(Track t, {String? exclude}) async {
    final c = exclude == null ? _ytIds[t.id] : null;
    if (c != null) return c;
    final q = '${t.artist} ${t.title}'.trim();
    List<String> words(String s) =>
        s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.length > 1).toList();
    final want = words(t.title).toSet();
    final who = words(t.artist).toSet();
    final want0 = q.toLowerCase();
    (Track?, double) pick(List<Track> res) {
      Track? best;
      var bestScore = -1e9;
      for (final r in res.take(10)) {
        if (r.id == exclude) continue;
        final have = words('${r.artist} ${r.title}').toSet();
        final hit = want.isEmpty ? 1.0 : want.where(have.contains).length / want.length;
        if (hit < 0.5) continue;
        final byArtist = who.isEmpty ? 1.0 : who.where(have.contains).length / who.length;
        final dd = t.seconds > 0 && r.seconds > 0 ? (r.seconds - t.seconds).abs() : 30;
        final raw = '${r.artist} ${r.title}'.toLowerCase();
        final junk = _junk.where((j) => raw.contains(j) && !want0.contains(j)).length;
        final score = hit * 10 + byArtist * 6 - dd / 6 - junk * 8;
        if (score > bestScore) {
          bestScore = score;
          best = r;
        }
      }
      return (best, bestScore);
    }

    String done(String id) => exclude == null ? (_ytIds[t.id] = id) : id;
    try {
      final (best, score) = pick(await YtmService.instance.searchSongs(q, limit: 10));
      if (best != null && score >= 11) return done(best.id);
    } catch (_) {}
    final res = await search(q);
    if (res.isEmpty) throw Exception(tr('пусто'));
    final alt = res.where((r) => r.id != exclude).toList();
    if (alt.isEmpty) throw Exception(tr('другого видео нет'));
    return done((pick(alt).$1 ?? alt.first).id);
  }

  Future<StreamPick> stream(String id, {bool economy = false, int from = 0}) async {
    Object? lastErr;
    for (var i = from; i < clients.length; i++) {
      try {
        return await streamWith(id, i, economy: economy);
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception(tr('YouTube не отдал поток: {0}', [_short(lastErr)]));
  }

  /// Поток одним способом (clients[i]); ошибка — с причиной.
  Future<StreamPick> streamWith(String id, int i, {bool economy = false, bool fresh = false}) async {
    final key = '$id/$economy/$i';
    final c = fresh ? null : _cache[key];
    // ссылка YouTube привязана к IP: сменилась сеть (Wi-Fi ↔ LTE, NAT оператора) — старая даёт 403,
    // поэтому держим недолго (20 мин), а при ошибке берём свежую (fresh)
    if (c != null && DateTime.now().difference(c.$2) < const Duration(minutes: 20)) return c.$1;
    Object? lastErr;
    {
      try {
        final cl = clients[i];
        final m = cl == null
            ? await _yt.videos.streamsClient.getManifest(id)
            : await _yt.videos.streamsClient.getManifest(id, ytClients: cl);
        // 1) чистый звук AAC — если YouTube отдаёт его целиком (с осени 2026 часто только начало файла,
        //    дальше 403 без защитного токена); 2) иначе совмещённый mp4 360p (itag 18) — его отдаёт целиком,
        //    плеер берёт из него только звук (трафика больше: ~4–5 МБ/мин)
        final audio = m.audioOnly.where((s) => s.container == StreamContainer.mp4).toList()
          ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
        final muxed = m.muxed.where((s) => s.container == StreamContainer.mp4).toList()
          ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
        final candidates = <StreamInfo>[
          if (audio.isNotEmpty) economy ? audio.first : audio.last,
          ...muxed,
        ];
        for (final s in candidates) {
          if (!await _wholeFileOpen(s.url, s.size.totalBytes)) continue;
          final mime = s is MuxedStreamInfo ? 'video/mp4' : s.codec.mimeType;
          final pick = StreamPick(s.url, s.size.totalBytes, mime, i);
          _cache[key] = (pick, DateTime.now());
          return pick;
        }
        lastErr = tr('отдаёт только начало потока');
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception(_short(lastErr));
  }

  /// Открывается ли кусок из середины файла (не только начало) — 2 байта.
  Future<bool> _wholeFileOpen(Uri url, int size) async {
    if (size <= 0) return false;
    final mid = size ~/ 2;
    try {
      final r = await http.get(url, headers: {'Range': 'bytes=$mid-${mid + 1}'}).timeout(const Duration(seconds: 8));
      return r.statusCode == 206 || r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Забыть ссылки на видео (они «протухли» — 403 после смены сети).
  void forget(String id) => _cache.removeWhere((k, _) => k.startsWith('$id/'));

  /// Для заранее подготовленного следующего трека.
  Future<Uri> streamUrl(String id, {bool economy = false}) async => (await stream(id, economy: economy)).url;
}

String _short(Object? e) {
  final s = '$e'.split('\n').first;
  return s.length > 120 ? '${s.substring(0, 120)}…' : s;
}
