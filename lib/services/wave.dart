import 'package:flutter/foundation.dart';

import '../i18n.dart';
import '../models.dart';
import 'audio.dart';
import 'store.dart';
import 'text_match.dart';
import 'yt.dart';
import 'ytm.dart';
import 'ytm_artist.dart';

/// «Моя волна»: бесконечный поток похожих треков. Старт — от того, что вы лайкали и слушали
/// (или по настроению); когда очередь подходит к концу, подгружаются «похожие» на текущий трек.
/// Всё — с одной площадки: радио YouTube Music (официальные треки, без перезаливов с SoundCloud).
class Wave extends ChangeNotifier {
  Wave._();
  static final Wave instance = Wave._();

  static const moods = <String, String>{
    'Энергичное': 'energetic phonk',
    'Спокойное': 'chill lofi',
    'Грустное': 'sad rap',
    'Тренировка': 'workout gym music',
    'Для сна': 'sleep ambient piano',
    'Русский рэп': 'русский рэп',
  };

  bool loading = false;
  String? mood;
  String? error;
  final _played = <String>{};
  bool _extending = false;

  bool get active => audio.nearEnd != null && audio.nearEnd == extend;

  Future<void> start({String? mood}) async {
    loading = true;
    error = null;
    this.mood = mood;
    notifyListeners();
    try {
      final first = await _firstBatch();
      if (first.isEmpty) throw Exception(tr('не нашлось треков'));
      first.shuffle();
      _played
        ..clear()
        ..addAll(first.map((t) => t.id));
      await audio.playList(first, 0, wave: extend);
    } catch (e) {
      error = tr('Волна не запустилась: {0}', ['$e'.replaceFirst('Exception: ', '')]);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Волна от готового списка (например, «Волна по исполнителю»): его треки вперемешку, дальше — похожие.
  Future<void> startWith(List<Track> seed, String label) async {
    if (seed.isEmpty) return;
    mood = label;
    error = null;
    final list = List.of(seed)..shuffle();
    _played
      ..clear()
      ..addAll(list.map((t) => t.id));
    await audio.playList(list, 0, wave: extend);
    notifyListeners();
  }

  void stop() {
    audio.nearEnd = null;
    notifyListeners();
  }

  Future<List<Track>> _firstBatch() async {
    final ytm = YtmService.instance;
    if (mood != null) {
      // по настроению: песни по запросу + радио от пары из них
      final found = _noJunk(await ytm.searchSongs(moods[mood]!, limit: 20), moods[mood]!);
      final out = [...found];
      for (final s in found.take(2)) {
        try {
          out.addAll(await relatedFor(s));
        } catch (_) {}
      }
      return _unique(out);
    }
    final st = Store.instance;
    final seeds = <Track>{...st.liked.take(20), ...st.history.take(20)}.toList();
    if (seeds.isEmpty) return _unique(await ytm.searchSongs('top hits 2026', limit: 25));
    seeds.shuffle();
    final out = <Track>[];
    for (final s in seeds.take(4)) {
      try {
        out.addAll((await relatedFor(s)).take(12));
      } catch (_) {}
      if (out.length >= 30) break;
    }
    return _unique(out);
  }

  static List<Track> _unique(List<Track> l) {
    final seen = <String>{};
    return [
      for (final t in l)
        if (seen.add(t.id)) t
    ];
  }

  /// Похожие на трек — радио YouTube Music от этой песни (у SoundCloud / импортированных — сначала та же
  /// песня на YouTube).
  Future<List<Track>> relatedFor(Track t) async {
    final vid = t.isYt ? t.id : await YtService.instance.findSame(t);
    final r = await YtmBrowse.instance.radio(vid);
    return _noJunk(r.where((x) => x.id != vid).toList(), '${t.artist} ${t.title}');
  }

  /// Без ускоренных/замедленных версий (если сам трек-образец не такой); концертные — в конец.
  static List<Track> _noJunk(List<Track> list, String seed) {
    final tags = {for (final x in list) x: Versions.extra('${x.artist} ${x.title}', seed)};
    final kept = list.where((x) => !tags[x]!.any(Versions.drop.contains)).toList();
    return [...kept.where((x) => tags[x]!.isEmpty), ...kept.where((x) => tags[x]!.isNotEmpty)];
  }

  /// Очередь подходит к концу — дописать ещё 10 похожих на текущий трек (без повторов).
  Future<void> extend() async {
    if (_extending) return;
    _extending = true;
    try {
      final cur = audio.current;
      if (cur == null) return;
      var more = (await relatedFor(cur)).where((t) => !_played.contains(t.id)).toList();
      if (more.length < 5 && mood != null && moods.containsKey(mood)) {
        more += (await YtmService.instance.searchSongs(moods[mood]!, limit: 25))
            .where((t) => !_played.contains(t.id))
            .toList();
      }
      more.shuffle();
      final add = more.take(10).toList();
      _played.addAll(add.map((t) => t.id));
      audio.append(add);
    } catch (_) {
      // нет сети — попробуем на следующем треке
    } finally {
      _extending = false;
    }
  }
}
