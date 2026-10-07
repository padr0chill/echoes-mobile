import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:echoes_eq/echoes_eq.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Всё, что приложение помнит: «Мне нравится», плейлисты, история, настройки.
/// Хранятся только названия и id треков (несколько килобайт), звук — никогда.
class Store extends ChangeNotifier {
  Store._();
  static final Store instance = Store._();

  late SharedPreferences _p;
  final List<Track> liked = [];
  final List<Playlist> playlists = [];
  final List<Track> history = [];
  final List<String> searches = [];

  static const accents = <Color>[
    Color(0xFFFFD43B), // жёлтый ECHOES
    Color(0xFFFF66AA),
    Color(0xFF7C8CFF),
    Color(0xFF3DDC97),
    Color(0xFFFF8A3D),
    Color(0xFF4FC3F7),
  ];
  int accentIndex = 0;
  bool economy = false; // экономия трафика: самый лёгкий поток
  bool light = false;

  // оформление
  String skin = 'glass'; // 'glass' — обычная (жидкое стекло), 'winamp' — как Winamp 2 на ПК
  bool vinyl = false; // в плеере вместо обложки — крутящийся винил с текстом песни под ним
  String? bgPath; // своё фото на фон (обычная тема)
  bool bgBlur = true;

  bool get winamp => skin == 'winamp';

  // вид плейлистов: порядок и сетка/список
  String playlistSort = 'order'; // order — как добавлены, recent — сначала новые, title, artist, duration
  bool playlistGrid = false; // false — список сверху вниз, true — сетка обложек слева направо
  // эквалайзер
  bool eqEnabled = false;
  List<double> eqGains = List.filled(10, 0.0);
  double eqPreamp = 0;
  String eqPreset = 'Плоский';
  bool milkdropText = true; // MilkDrop «вжигает» строки текста песни в картинку (как на ПК)

  // профиль и статистика
  String name = 'Слушатель';
  int plays = 0; // сколько треков включали
  int listenSeconds = 0; // сколько секунд реально слушали
  final Map<String, int> artistSeconds = {}; // исполнитель → секунды
  final Set<String> listenedIds = {}; // разные треки (для «уникальных»)

  Color get accent => winamp ? const Color(0xFF00E000) : accents[accentIndex.clamp(0, accents.length - 1)];

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    List<Track> tracks(String key) {
      final s = _p.getString(key);
      if (s == null) return [];
      return (jsonDecode(s) as List).map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }

    liked
      ..clear()
      ..addAll(tracks('liked'));
    history
      ..clear()
      ..addAll(tracks('history'));
    final pl = _p.getString('playlists');
    playlists.clear();
    if (pl != null) {
      playlists.addAll((jsonDecode(pl) as List).map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map))));
    }
    searches
      ..clear()
      ..addAll(_p.getStringList('searches') ?? []);
    accentIndex = _p.getInt('accent') ?? 0;
    economy = _p.getBool('economy') ?? false;
    light = _p.getBool('light') ?? false;
    skin = _p.getString('skin') ?? 'glass';
    vinyl = _p.getBool('vinyl') ?? false;
    bgPath = _p.getString('bg');
    bgBlur = _p.getBool('bg_blur') ?? true;
    playlistSort = _p.getString('pl_sort') ?? 'order';
    playlistGrid = _p.getBool('pl_grid') ?? false;
    milkdropText = _p.getBool('md_text') ?? true;
    eqEnabled = _p.getBool('eq_on') ?? false;
    final g = _p.getStringList('eq_gains');
    if (g != null && g.length == 10) eqGains = g.map((s) => double.tryParse(s) ?? 0).toList();
    eqPreamp = _p.getDouble('eq_pre') ?? 0;
    eqPreset = _p.getString('eq_preset') ?? 'Плоский';
    name = _p.getString('name') ?? 'Слушатель';
    plays = _p.getInt('plays') ?? 0;
    listenSeconds = _p.getInt('listen_s') ?? 0;
    artistSeconds.clear();
    final as = _p.getString('artist_s');
    if (as != null) {
      (jsonDecode(as) as Map).forEach((k, v) => artistSeconds['$k'] = (v as num).toInt());
    }
    listenedIds
      ..clear()
      ..addAll(_p.getStringList('listened') ?? []);
  }

  void _save() {
    _p.setString('liked', jsonEncode(liked.map((t) => t.toJson()).toList()));
    _p.setString('history', jsonEncode(history.map((t) => t.toJson()).toList()));
    _p.setString('playlists', jsonEncode(playlists.map((p) => p.toJson()).toList()));
    _p.setStringList('searches', searches);
    _p.setInt('accent', accentIndex);
    _p.setBool('economy', economy);
    _p.setBool('light', light);
    _p.setString('skin', skin);
    _p.setBool('vinyl', vinyl);
    if (bgPath == null) {
      _p.remove('bg');
    } else {
      _p.setString('bg', bgPath!);
    }
    _p.setBool('bg_blur', bgBlur);
    _p.setString('pl_sort', playlistSort);
    _p.setBool('pl_grid', playlistGrid);
    _p.setBool('md_text', milkdropText);
    _p.setBool('eq_on', eqEnabled);
    _p.setStringList('eq_gains', eqGains.map((v) => v.toStringAsFixed(1)).toList());
    _p.setDouble('eq_pre', eqPreamp);
    _p.setString('eq_preset', eqPreset);
    _p.setString('name', name);
    _p.setInt('plays', plays);
    _p.setInt('listen_s', listenSeconds);
    _p.setString('artist_s', jsonEncode(artistSeconds));
    _p.setStringList('listened', listenedIds.toList());
    notifyListeners();
  }

  void setName(String v) {
    if (v.trim().isEmpty) return;
    name = v.trim();
    _save();
  }

  /// Трек слушали s секунд (при переключении или в конце).
  void addListened(Track t, int s) {
    if (s <= 0) return;
    listenSeconds += s;
    final a = t.artist.trim().isEmpty ? '—' : t.artist.trim();
    artistSeconds[a] = (artistSeconds[a] ?? 0) + s;
    if (artistSeconds.length > 300) {
      final keep = topArtists(200);
      artistSeconds.removeWhere((k, _) => !keep.contains(k));
    }
    _save();
  }

  /// Любимые исполнители по времени прослушивания.
  List<String> topArtists([int n = 5]) {
    final e = artistSeconds.entries.where((e) => e.key != '—').toList()..sort((a, b) => b.value.compareTo(a.value));
    return e.take(n).map((e) => e.key).toList();
  }

  void clearHistory() {
    history.clear();
    _save();
  }

  bool isLiked(Track t) => liked.contains(t);

  void toggleLike(Track t) {
    if (!liked.remove(t)) liked.insert(0, t);
    _save();
  }

  void addHistory(Track t) {
    plays++;
    listenedIds.add(t.id);
    if (listenedIds.length > 5000) listenedIds.remove(listenedIds.first);
    history.remove(t);
    history.insert(0, t);
    if (history.length > 100) history.removeRange(100, history.length);
    _save();
  }

  void addSearch(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    searches.remove(q);
    searches.insert(0, q);
    if (searches.length > 12) searches.removeRange(12, searches.length);
    _save();
  }

  void clearSearches() {
    searches.clear();
    _save();
  }

  Playlist createPlaylist(String name) {
    final p = Playlist(name.trim().isEmpty ? 'Новый плейлист' : name.trim());
    playlists.insert(0, p);
    _save();
    return p;
  }

  void renamePlaylist(Playlist p, String name) {
    if (name.trim().isEmpty) return;
    p.name = name.trim();
    _save();
  }

  void deletePlaylist(Playlist p) {
    playlists.remove(p);
    _save();
  }

  void addToPlaylist(Playlist p, Track t) {
    if (!p.tracks.contains(t)) p.tracks.add(t);
    _save();
  }

  void removeFromPlaylist(Playlist p, Track t) {
    p.tracks.remove(t);
    _save();
  }

  /// Импорт с ПК: «Мне нравится» сливается с лайками, плейлист с тем же именем — дополняется,
  /// остальные создаются. → сколько треков добавлено.
  int importPlaylists(List<(String, List<Track>)> lists) {
    var added = 0;
    for (final (name, tracks) in lists) {
      if (name.trim().toLowerCase() == 'мне нравится') {
        final have = liked.toSet();
        for (final t in tracks) {
          if (have.add(t)) {
            liked.add(t);
            added++;
          }
        }
        continue;
      }
      var p = playlists.where((p) => p.name == name).firstOrNull;
      if (p == null) {
        p = Playlist(name.trim().isEmpty ? 'С компьютера' : name.trim());
        playlists.add(p);
      }
      final have = p.tracks.toSet();
      for (final t in tracks) {
        if (have.add(t)) {
          p.tracks.add(t);
          added++;
        }
      }
    }
    _save();
    return added;
  }

  String? get scClientId => _p.getString('sc_cid');
  void setScClientId(String v) => _p.setString('sc_cid', v);

  void setAccent(int i) {
    accentIndex = i;
    _save();
  }

  void setEconomy(bool v) {
    economy = v;
    _save();
  }

  void setPlaylistView({String? sort, bool? grid}) {
    if (sort != null) playlistSort = sort;
    if (grid != null) playlistGrid = grid;
    _save();
  }

  /// Эквалайзер: сохранить и сразу применить к звуку.
  void setEq({bool? enabled, List<double>? gains, double? preamp, String? preset}) {
    if (enabled != null) eqEnabled = enabled;
    if (gains != null) eqGains = List.of(gains);
    if (preamp != null) eqPreamp = preamp;
    if (preset != null) eqPreset = preset;
    _save();
    EchoesEq.apply(gains: eqGains, preamp: eqPreamp, enabled: eqEnabled);
  }

  void setMilkdropText(bool v) {
    milkdropText = v;
    _save();
  }

  void setSkin(String v) {
    skin = v;
    _save();
  }

  void setVinyl(bool v) {
    vinyl = v;
    _save();
  }

  void setBackground(String? path) {
    bgPath = path;
    _save();
  }

  void setBgBlur(bool v) {
    bgBlur = v;
    _save();
  }

  void setLight(bool v) {
    light = v;
    _save();
  }
}
