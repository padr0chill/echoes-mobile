import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'text_match.dart';

/// Эталонные длительности песен (как в Spotify): официальный каталог Deezer (открытый API, без ключей).
/// По ним видно перезаливы «slowed» / «sped up» без пометок в названии: та же песня, а длительность другая.
class Reference {
  Reference._();
  static final Reference instance = Reference._();

  final _cache = <String, Future<List<Track>>>{};

  /// Официальные треки по запросу (исполнитель, название, длительность). Ошибка сети — пустой список.
  Future<List<Track>> lookup(String q) => _cache[q.toLowerCase().trim()] ??= () async {
        try {
          final r = await http
              .get(Uri.https('api.deezer.com', '/search', {'q': q, 'limit': '15'}))
              .timeout(const Duration(seconds: 6));
          if (r.statusCode != 200) return <Track>[];
          final data = (jsonDecode(r.body) as Map)['data'] as List? ?? [];
          return [
            for (final x in data.cast<Map>())
              Track(
                id: 'dz:${x['id']}',
                title: '${x['title'] ?? ''}',
                artist: '${(x['artist'] as Map?)?['name'] ?? ''}',
                seconds: ((x['duration'] ?? 0) as num).toInt(),
              ),
          ];
        } catch (_) {
          return <Track>[];
        }
      }();

  static String _n(String s) => Versions.plain(s)
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
      .replaceAll(RegExp(r'\b(feat|ft|prod)\b.*$'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  /// Это та же песня, что эталон r? Слова названия эталона есть в тексте трека и совпадает исполнитель
  /// (у перезаливов SoundCloud исполнитель часто в названии: «zxcursed - где»).
  static bool sameSong(Track t, Track r) {
    final rt = _n(r.title).split(' ').where((w) => w.isNotEmpty).toList();
    if (rt.isEmpty) return false;
    final text = ' ${_n('${t.artist} ${t.title}')} ';
    final title = ' ${_n(t.title)} ';
    if (!rt.every((w) => text.contains(' $w '))) return false;
    // название трека не должно быть заметно длиннее эталонного (иначе это другая песня с похожим именем)
    final extra = title.trim().split(' ').where((w) => w.isNotEmpty && !rt.contains(w)).length;
    final artistWords = _n(r.artist).split(' ').where((w) => w.length > 1).toList();
    final artistHit = artistWords.isEmpty ||
        artistWords.any((w) => text.contains(' $w ')) ||
        TextMatch.similarity(t.artist, r.artist) >= 0.6;
    return artistHit && extra <= 3;
  }

  /// Подходящие эталоны: та же песня и та же «версия» (концертная с концертной, оригинал с оригиналом).
  static List<int> _durations(Track t, List<Track> refs) {
    final tags = Versions.of('${t.artist} ${t.title}');
    return [
      for (final r in refs)
        if (r.seconds > 0 &&
            sameSong(t, r) &&
            Versions.of(r.title).length == tags.length &&
            Versions.of(r.title).containsAll(tags))
          r.seconds
    ]..sort();
  }

  /// Эталонная длительность (медиана подходящих эталонов) или null.
  static int? canonical(Track t, List<Track> refs) {
    final d = _durations(t, refs);
    return d.isEmpty ? null : d[d.length ~/ 2];
  }

  /// Длительность «не та»: далеко (больше 6 % и минимум 6 с) от ВСЕХ подходящих эталонов — значит ускорена
  /// или замедлена (sped up ≈ −15…−25 %, slowed ≈ +15…+30 %). Альбомная и сингл-версия — обе в эталонах.
  static bool altered(Track t, List<Track> refs) {
    if (t.seconds <= 0) return false;
    final d = _durations(t, refs);
    if (d.isEmpty) return false;
    return d.every((c) => (t.seconds - c).abs() > (c * 0.06 < 6 ? 6 : c * 0.06));
  }
}
