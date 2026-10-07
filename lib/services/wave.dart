import 'package:flutter/foundation.dart';

import '../models.dart';
import 'audio.dart';
import 'sc.dart';
import 'store.dart';

/// «Моя волна»: бесконечный поток похожих треков. Старт — от того, что вы лайкали и слушали
/// (или по настроению); когда очередь подходит к концу, подгружаются «похожие» на текущий трек.
/// Похожие берутся у SoundCloud — это настоящие песни, и они сразу полные (не зависят от YouTube).
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
      if (first.isEmpty) throw Exception('не нашлось треков');
      first.shuffle();
      _played
        ..clear()
        ..addAll(first.map((t) => t.id));
      await audio.playList(first, 0, wave: extend);
    } catch (e) {
      error = 'Волна не запустилась: ${'$e'.replaceFirst('Exception: ', '')}';
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
    final sc = ScService.instance;
    if (mood != null) return sc.searchTracks(moods[mood]!, limit: 40);
    final st = Store.instance;
    final seeds = <Track>{...st.liked.take(20), ...st.history.take(20)}.toList();
    if (seeds.isEmpty) return sc.searchTracks('top hits 2026', limit: 40);
    seeds.shuffle();
    final out = <Track>[];
    for (final s in seeds.take(4)) {
      try {
        out.addAll(await relatedFor(s));
      } catch (_) {}
      if (out.length >= 25) break;
    }
    final seen = <String>{};
    return out.where((t) => seen.add(t.id)).toList();
  }

  /// Похожие на трек: у SoundCloud-трека — сразу; у YouTube — сначала находим ту же песню на SoundCloud.
  Future<List<Track>> relatedFor(Track t) async {
    final sc = ScService.instance;
    final id = t.isSc ? t.scId : (await sc.match(t.artist, t.title, t.seconds, strict: false))?.id;
    if (id == null) return sc.searchTracks(t.artist, limit: 20);
    return sc.related(id);
  }

  /// Очередь подходит к концу — дописать ещё 10 похожих на текущий трек (без повторов).
  Future<void> extend() async {
    if (_extending) return;
    _extending = true;
    try {
      final cur = audio.current;
      if (cur == null) return;
      var more = (await relatedFor(cur)).where((t) => !_played.contains(t.id)).toList();
      if (more.length < 5 && mood != null) {
        more += (await ScService.instance.searchTracks('${moods[mood]} ${DateTime.now().millisecond}', limit: 40))
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
