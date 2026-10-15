import '../models.dart';
import 'reference.dart';
import 'sc.dart';
import 'text_match.dart';
import 'yt.dart';
import 'ytm.dart';

enum SearchSource { all, ytm, yt, sc }

/// Поиск по площадкам: «Все» = YouTube Music + SoundCloud вместе.
/// Ускоренные/замедленные версии убираются, ремиксы и каверы — в конец (если их не искали специально).
class SearchService {
  SearchService._();

  /// «Красивые» шрифты (𝒔𝒍𝒐𝒘𝒆𝒅, ｓｌｏｗｅｄ, 𝕤𝕝𝕠𝕨𝕖𝕕) → обычные буквы, чтобы фильтр их видел.
  static String plain(String s) => Versions.plain(s);

  static String _norm(String s) => plain(s)
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  /// Замедленные/ускоренные и т. п. — убрать; концертные, ремиксы, каверы — в конец (если их не искали).
  static List<Track> clean(String q, List<Track> list) {
    final tags = {for (final t in list) t: Versions.extra('${t.artist} ${t.title}', q)};
    final wantLong = RegExp(r'album|mix|альбом|сборник|подборк', caseSensitive: false).hasMatch(q);
    // целые альбомы/миксы на час-два — только если их и искали
    final wantSnip = Versions.of(q).contains('snippet');
    // обрывки по 15–40 с (перезаливы-«сниппеты») — не песни; целиком убираем, если их не искали
    final kept = list
        .where((t) => !tags[t]!.any(Versions.drop.contains) && (wantLong || t.seconds <= 1200))
        .where((t) => wantSnip || !(t.seconds > 0 && t.seconds < 40) && !tags[t]!.contains('snippet'))
        .toList();
    bool odd(Track t) => tags[t]!.isNotEmpty || (t.seconds > 0 && t.seconds < 55);
    final main = kept.where((t) => !odd(t)).toList();
    final rest = kept.where(odd).toList();
    return [...main, ...rest];
  }

  /// Та же песня (для склейки результатов YouTube Music и SoundCloud).
  static bool same(Track a, Track b) {
    final ta = _norm(a.title), tb = _norm(b.title);
    if (ta.isEmpty || ta != tb) return false;
    // «Numb» и «Numb (Live)» — разные записи, хоть без скобок названия совпадают
    if (!Versions.of('${a.artist} ${a.title}').containsAll(Versions.of('${b.artist} ${b.title}')) ||
        !Versions.of('${b.artist} ${b.title}').containsAll(Versions.of('${a.artist} ${a.title}'))) {
      return false;
    }
    // «theneighbourhood» = «The Neighbourhood»: сравниваем без пробелов
    final ca = _norm(a.artist).replaceAll(' ', ''), cb = _norm(b.artist).replaceAll(' ', '');
    final wa = _norm(a.artist).split(' ').toSet(), wb = _norm(b.artist).split(' ').toSet();
    if (!wa.any(wb.contains) && !(ca.isNotEmpty && cb.isNotEmpty && (ca.contains(cb) || cb.contains(ca)))) return false;
    return a.seconds == 0 || b.seconds == 0 || (a.seconds - b.seconds).abs() <= 8;
  }

  /// Сначала то, где есть все слова запроса (в исполнителе или названии), потом частичные, потом остальное;
  /// внутри группы — исходный порядок площадки.
  static List<Track> rank(String q, List<Track> list) {
    final words = _norm(q).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return list;
    int group(Track t) {
      final text = _norm('${t.artist} ${t.title}');
      final compact = text.replaceAll(' ', '');
      final n = words.where((w) => text.split(' ').any((x) => x.startsWith(w)) || compact.contains(w)).length;
      return n == words.length ? 0 : (n > 0 ? 1 : 2);
    }

    final g = {for (final t in list) t: group(t)};
    final idx = {for (var i = 0; i < list.length; i++) list[i]: i};
    return [...list]..sort((a, b) {
        final c = g[a]!.compareTo(g[b]!);
        return c != 0 ? c : idx[a]!.compareTo(idx[b]!);
      });
  }

  /// Поиск + проверка длительности по эталону (Deezer — официальные длительности, как в Spotify):
  /// та же песня заметно короче/длиннее эталона — перезалив sped up / slowed, даже без пометки в названии.
  static Future<List<Track>> search(String q, SearchSource src) async {
    final refF = Reference.instance.lookup(q);
    final res = await _search(q, src);
    final wantAltered = Versions.of(q).any(Versions.drop.contains);
    if (wantAltered) return rank(q, _dedupe(res));
    final refs = await refF.timeout(const Duration(seconds: 3), onTimeout: () => <Track>[]);
    return rank(q, _dedupe(filterAltered(res, refs)));
  }

  /// Одна и та же запись дважды (альбом и сингл с тем же звуком) — оставляем первую.
  static List<Track> _dedupe(List<Track> list) {
    final seen = <String>{};
    return [
      for (final t in list)
        if (seen.add('${_norm(t.artist)}|${_norm(t.title)}|${(t.seconds / 4).round()}')) t
    ];
  }

  /// Убрать «не той длительности» (если эталона нет — оставить как есть).
  static List<Track> filterAltered(List<Track> list, List<Track> refs) =>
      refs.isEmpty ? list : list.where((t) => !Reference.altered(t, refs)).toList();

  static Future<List<Track>> _search(String q, SearchSource src) async {
    switch (src) {
      case SearchSource.ytm:
        return clean(q, await YtmService.instance.searchSongs(q));
      case SearchSource.yt:
        return clean(q, await YtService.instance.search(q));
      case SearchSource.sc:
        return clean(q, await ScService.instance.searchTracks(q));
      case SearchSource.all:
        final r = await Future.wait([
          YtmService.instance.searchSongs(q).then<List<Track>?>((v) => v).catchError((_) => null),
          ScService.instance.searchTracks(q).then<List<Track>?>((v) => v).catchError((_) => null),
        ]);
        var ytm = r[0], sc = r[1];
        if (ytm == null && sc == null) {
          return clean(q, await YtService.instance.search(q)); // обе площадки недоступны — обычный YouTube
        }
        ytm = clean(q, ytm ?? []);
        sc = clean(q, sc ?? []);
        // порядок — как у YouTube Music (он лучше понимает запрос); если та же песня есть на SoundCloud
        // целиком — берём её: с SoundCloud звук на телефоне открывается надёжнее
        final used = <Track>{};
        final out = <Track>[];
        for (final t in ytm) {
          final twin = sc.where((s) => !used.contains(s) && same(t, s)).firstOrNull;
          if (twin != null) {
            used.add(twin);
            out.add(Track(
                id: twin.id,
                title: t.title,
                artist: t.artist,
                seconds: twin.seconds,
                art: t.art ?? twin.art,
                artistId: twin.artistId));
          } else {
            out.add(t);
          }
        }
        // остальное с SoundCloud (то, чего нет на YouTube Music) — следом, вперемешку с хвостом
        // перезаливы («top_myzik — Miyagi & Andy Panda - Kosandra») той же песни, что уже есть, — не нужны
        String c(String s) => _norm(s).replaceAll(' ', '');
        bool reupload(Track s) => out.any((o) {
              final all = c('${s.artist} ${s.title}');
              return c(o.artist).isNotEmpty &&
                  all.contains(c(o.artist)) &&
                  all.contains(c(o.title)) &&
                  (s.seconds - o.seconds).abs() <= 8;
            });
        final extra = sc.where((s) => !used.contains(s) && !reupload(s)).toList();
        if (out.isEmpty) return extra;
        final res = <Track>[];
        var i = 0, j = 0;
        while (i < out.length || j < extra.length) {
          for (var k = 0; k < 3 && i < out.length; k++) {
            res.add(out[i++]);
          }
          if (j < extra.length) res.add(extra[j++]);
        }
        return res;
    }
  }
}
