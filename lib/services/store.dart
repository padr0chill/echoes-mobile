import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:echoes_eq/echoes_eq.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../i18n.dart';

/// Всё, что приложение помнит: «Мне нравится», плейлисты, история, настройки.
/// Хранятся только названия и id треков (несколько килобайт), звук — никогда.
class Store extends ChangeNotifier {
  Store._();
  static final Store instance = Store._();

  late SharedPreferences _p;
  final List<Track> liked = [];
  final List<Playlist> playlists = [];

  /// Подписки на исполнителей: имя, канал YouTube Music, фото (новые — сверху).
  final List<Map<String, String>> follows = [];
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
  String skin = 'phantom';
  String lang = 'auto'; // язык интерфейса: 'auto' (как на iPhone), 'ru', 'en'
  double crossfade = 0; // плавный переход между треками, секунды (0 — выкл)
  bool vinyl = false; // в плеере вместо обложки — крутящийся винил с текстом песни под ним
  /// Своё фото на фон (обычная тема) — имя файла в папке приложения: на iOS путь к папке меняется
  /// после обновления, абсолютный путь «потерял» бы фон.
  String? bgFile;
  String? get bgPath => bgFile == null || supportDir == null ? null : '$supportDir/$bgFile';
  bool bgBlur = true;
  double bgBlurAmount = 1; // сила размытия фона 0…1

  bool get winamp => skin == 'winamp';
  bool get phantom => skin == 'phantom';

  // вид плейлистов: порядок и сетка/список
  String playlistSort = 'order'; // order — как добавлены, recent — сначала новые, title, artist, duration
  String librarySort = 'custom'; // «Моя музыка»: custom — свой порядок, recent — недавние, alpha — по алфавиту
  bool libraryGrid = false; // плейлисты сеткой обложек
  /// Папка данных приложения (на iOS её путь меняется после обновления — храним только имена файлов).
  static String? supportDir;
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

  Color get accent => switch (skin) {
    'phantom' => const Color(0xFFF5F5F5),
    'winamp' => const Color(0xFF00E000),
    _ => accents[accentIndex.clamp(0, accents.length - 1)],
  };

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    ready = true;
    List<Track> tracks(String key) => _list(key, Track.fromJson);

    liked
      ..clear()
      ..addAll(tracks('liked'));
    history
      ..clear()
      ..addAll(tracks('history'));
    follows
      ..clear()
      ..addAll(_list('follows', (m) => {for (final e in m.entries) e.key: '${e.value}'}));
    playlists
      ..clear()
      ..addAll(_list('playlists', Playlist.fromJson));
    searches
      ..clear()
      ..addAll(_strings('searches'));
    accentIndex = _int('accent') ?? 0;
    economy = _bool('economy') ?? false;
    light = _bool('light') ?? false;
    final savedSkin = _str('appearance_skin');
    skin = switch (savedSkin) {
      'glass' || 'winamp' || 'phantom' => savedSkin!,
      _ => _str('skin') == 'winamp' ? 'winamp' : 'phantom',
    };
    lang = appLangSetting = _str('lang') ?? appLangSetting;
    vinyl = _bool('vinyl') ?? false;
    crossfade = _dbl('xfade') ?? 0;
    bgFile = _str('bg')?.split(RegExp(r'[/\\]')).last; // раньше хранился полный путь — берём имя
    bgBlur = _bool('bg_blur') ?? true;
    bgBlurAmount = _dbl('bg_blur_k') ?? (bgBlur ? 1.0 : 0.0);
    playlistSort = _str('pl_sort') ?? 'order';
    playlistGrid = _bool('pl_grid') ?? false;
    librarySort = _str('lib_sort') ?? 'custom';
    libraryGrid = _bool('lib_grid') ?? false;
    milkdropText = _bool('md_text') ?? true;
    eqEnabled = _bool('eq_on') ?? false;
    final g = _strings('eq_gains');
    if (g.length == 10) eqGains = g.map((s) => double.tryParse(s) ?? 0).toList();
    eqPreamp = _dbl('eq_pre') ?? 0;
    eqPreset = _str('eq_preset') ?? 'Плоский';
    name = _str('name') ?? 'Слушатель';
    plays = _int('plays') ?? 0;
    listenSeconds = _int('listen_s') ?? 0;
    artistSeconds.clear();
    final as = _str('artist_s');
    if (as != null) {
      try {
        (jsonDecode(as) as Map).forEach((k, v) {
          if (v is num) artistSeconds['$k'] = v.toInt();
        });
      } catch (_) {
        _keepBroken('artist_s', as);
      }
    }
    listenedIds
      ..clear()
      ..addAll(_strings('listened'));
  }

  // ── чтение настроек без падений: одно испорченное значение не должно «окирпичить» запуск ──

  /// Оригинал испорченного значения — под другим ключом, пока _save() не перезаписал (можно вытащить).
  void _keepBroken(String key, String raw) {
    try {
      _p.setString('${key}_broken', raw);
    } catch (_) {}
  }

  Object? _raw(String key) {
    try {
      return _p.get(key);
    } catch (_) {
      return null;
    }
  }

  String? _str(String key) {
    final v = _raw(key);
    return v is String ? v : null;
  }

  bool? _bool(String key) {
    final v = _raw(key);
    return v is bool ? v : null;
  }

  int? _int(String key) {
    final v = _raw(key);
    return v is num ? v.toInt() : null;
  }

  double? _dbl(String key) {
    final v = _raw(key);
    return v is num ? v.toDouble() : null;
  }

  List<String> _strings(String key) {
    final v = _raw(key);
    return v is List ? [for (final x in v) '$x'] : [];
  }

  /// Список из JSON: битый элемент пропускается (а не весь список), оригинал — в `<key>_broken`.
  List<T> _list<T>(String key, T Function(Map<String, dynamic>) parse) {
    final s = _str(key);
    if (s == null) return [];
    final out = <T>[];
    var lost = false;
    try {
      final raw = jsonDecode(s);
      if (raw is! List) throw const FormatException('not a list');
      for (final e in raw) {
        try {
          out.add(parse(Map<String, dynamic>.from(e as Map)));
        } catch (_) {
          lost = true;
        }
      }
    } catch (_) {
      lost = true;
    }
    if (lost) _keepBroken(key, s);
    return out;
  }

  /// Через сколько записать изменения на диск. Шаг ползунка, лайк, смена трека — интерфейс обновляется
  /// сразу, а запись (лайки, история, плейлисты — сотни треков в JSON) — одна на серию изменений.
  /// В тестах — сразу (Duration.zero), чтобы не оставлять таймеров.
  static Duration saveDelay = const Duration(milliseconds: 400);
  Timer? _saveTimer;

  void _save() {
    notifyListeners();
    if (saveDelay == Duration.zero) {
      _write();
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, _write);
  }

  /// Записать отложенное сейчас (приложение уходит в фон — потом его могут закрыть без предупреждения).
  void flush() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _write();
    }
  }

  void _write() {
    _saveTimer = null;
    if (!ready) return;
    _p.setString('liked', jsonEncode(liked.map((t) => t.toJson()).toList()));
    _p.setString('history', jsonEncode(history.map((t) => t.toJson()).toList()));
    _p.setString('playlists', jsonEncode(playlists.map((p) => p.toJson()).toList()));
    _p.setString('follows', jsonEncode(follows));
    _p.setStringList('searches', searches);
    _p.setInt('accent', accentIndex);
    _p.setBool('economy', economy);
    _p.setBool('light', light);
    _p.setString('appearance_skin', skin);
    _p.setString('lang', lang);
    _p.setBool('vinyl', vinyl);
    _p.setDouble('xfade', crossfade);
    if (bgFile == null) {
      _p.remove('bg');
    } else {
      _p.setString('bg', bgFile!);
    }
    _p.setBool('bg_blur', bgBlur);
    _p.setDouble('bg_blur_k', bgBlurAmount);
    _p.setString('pl_sort', playlistSort);
    _p.setBool('pl_grid', playlistGrid);
    _p.setString('lib_sort', librarySort);
    _p.setBool('lib_grid', libraryGrid);
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
    final p = Playlist(name.trim().isEmpty ? tr('Новый плейлист') : name.trim());
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
    p.touched = DateTime.now().millisecondsSinceEpoch;
    _save();
  }

  /// Плейлист открыли/включили — наверх в «Недавних».
  void touchPlaylist(Playlist p) {
    p.touched = DateTime.now().millisecondsSinceEpoch;
    _save();
  }

  /// Своя обложка (имя файла в playlist_covers) или null — собрать из обложек треков.
  void setPlaylistCover(Playlist p, String? file) {
    p.cover = file;
    _save();
  }

  /// Свой порядок плейлистов (перетаскивание в «Моей музыке»).
  void movePlaylist(int from, int to) {
    if (from < 0 || from >= playlists.length) return;
    final p = playlists.removeAt(from);
    playlists.insert(to.clamp(0, playlists.length), p);
    _save();
  }

  /// Что играло и очередь — переживают перезапуск приложения (JSON).
  bool ready = false; // настройки загружены (в тестах может не быть)
  String? get session => ready ? _str('session') : null;
  void saveSession(String json) => _p.setString('session', json);

  /// Позиция в треке — отдельным маленьким ключом (пишется каждые 5 с, очередь при этом не трогается).
  String? get sessionPos => ready ? _str('session_pos') : null;
  void saveSessionPos(String json) => _p.setString('session_pos', json);

  bool isFollowing(String name) => follows.any((f) => f['name']?.toLowerCase() == name.toLowerCase());

  /// Подписаться / отписаться.
  void toggleFollow(String name, {String? ytm, String? image}) {
    if (isFollowing(name)) {
      follows.removeWhere((f) => f['name']?.toLowerCase() == name.toLowerCase());
    } else {
      follows.insert(0, {'name': name, 'ytm': ?ytm, 'img': ?image});
    }
    _save();
  }

  void setLibraryView({String? sort, bool? grid}) {
    if (sort != null) librarySort = sort;
    if (grid != null) libraryGrid = grid;
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
        p = Playlist(name.trim().isEmpty ? tr('С компьютера') : name.trim());
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

  String? get scClientId => _str('sc_cid');
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

  void setLang(String v) {
    lang = appLangSetting = v;
    _save();
  }

  void setSkin(String v) {
    skin = v;
    _save();
  }

  void setCrossfade(double v) {
    crossfade = v;
    _save();
  }

  void setVinyl(bool v) {
    vinyl = v;
    _save();
  }

  void setBackground(String? path) {
    bgFile = path?.split(RegExp(r'[/\\]')).last;
    _save();
  }

  void setBgBlurAmount(double v) {
    bgBlurAmount = v;
    bgBlur = v > 0;
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
