import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models.dart';

/// Поиск и аудиопоток YouTube прямо на телефоне. Ничего не скачивается: плееру отдаётся ссылка на поток,
/// он берёт звук небольшими кусками по мере прослушивания.
class YtService {
  YtService._();
  static final YtService instance = YtService._();

  final _yt = YoutubeExplode();
  final _urls = <String, (Uri, DateTime)>{};

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

  /// Ссылка на аудиопоток. AAC (mp4) — его играет iOS; «экономия» — самый лёгкий поток.
  Future<Uri> streamUrl(String id, {bool economy = false}) async {
    final key = '$id/$economy';
    final c = _urls[key];
    if (c != null && DateTime.now().difference(c.$2) < const Duration(hours: 2)) return c.$1;
    // по умолчанию — быстрее всего (~1,5 с); другие клиенты — запасные, если YouTube откажет
    StreamManifest? m;
    Object? lastErr;
    for (final clients in <List<YoutubeApiClient>?>[
      null,
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.ios],
    ]) {
      try {
        m = clients == null
            ? await _yt.videos.streamsClient.getManifest(id)
            : await _yt.videos.streamsClient.getManifest(id, ytClients: clients);
        if (m.audioOnly.isNotEmpty) break;
      } catch (e) {
        lastErr = e;
      }
    }
    if (m == null) throw Exception('поток недоступен: $lastErr');
    var list = m.audioOnly.where((s) => s.container == StreamContainer.mp4).toList();
    if (list.isEmpty) list = m.audioOnly.toList();
    if (list.isEmpty) throw Exception('нет аудиопотока');
    list.sort((a, b) => a.bitrate.compareTo(b.bitrate));
    final url = (economy ? list.first : list.last).url;
    _urls[key] = (url, DateTime.now());
    return url;
  }
}
