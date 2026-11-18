import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:echoes_eq/echoes_eq.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'audio_zip.dart';
import 'sc.dart';
import 'yt.dart';
import '../i18n.dart';
import 'log.dart';

/// Загрузки «для офлайна» — как в Spotify / Яндекс Музыке: звук сохраняется во внутреннее хранилище
/// приложения (Application Support/offline), а не в «Файлы» и не в медиатеку. Снаружи этих файлов не видно,
/// играет их только ECHOES; удаляются вместе с приложением или кнопкой «Очистить загрузки».
class Offline extends ChangeNotifier {
  Offline._();
  static final Offline instance = Offline._();

  /// id трека → (имя файла, байты, трек).
  final Map<String, (String, int, Track)> _items = {};
  final Map<String, double> progress = {}; // id → 0..1, пока качается
  final Map<String, String> failed = {}; // id → причина
  final List<Track> _queue = [];
  int _running = 0;
  Directory? _dir;
  static const _parallel = 3; // треков одновременно (у каждого ещё по 6 соединений)

  /// Для тестов: забыть всё в памяти (папка будет взята заново).
  @visibleForTesting
  void resetForTest() {
    _items.clear();
    _queue.clear();
    progress.clear();
    failed.clear();
    _dir = null;
  }

  final _client = http.Client();

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/offline');
    if (!d.existsSync()) d.createSync(recursive: true);
    if (!kIsWeb && Platform.isIOS) EchoesEq.excludeFromBackup(d.path).ignore(); // не в iCloud
    return _dir = d;
  }

  File get _index => File('${_dir!.path}/index.json');

  Future<void> load() async {
    final d = await _folder();
    // на старте ничего не качается — недокачанные куски прочь
    try {
      for (final f in d.listSync().whereType<File>()) {
        if (f.path.endsWith('.part') || f.path.endsWith('.tmp')) f.deleteSync();
      }
    } catch (e) {
      log.w('offline:49', e);
    }
    if (!_index.existsSync()) return;
    Map j;
    try {
      j = jsonDecode(_index.readAsStringSync()) as Map;
    } catch (_) {
      // индекс испорчен целиком — сохранить как есть (следующая запись его не затрёт), начать заново
      try {
        _index.renameSync('${d.path}/index.json.broken');
      } catch (e) {
        log.w('offline:58', e);
      }
      return;
    }
    // каждая запись отдельно: одна битая не отменяет остальные
    j.forEach((id, v) {
      try {
        final m = v as Map;
        final f = File('${d.path}/${m['f']}');
        if (f.existsSync()) {
          _items['$id'] = (
            '${m['f']}',
            (m['b'] as num).toInt(),
            Track.fromJson(Map<String, dynamic>.from(m['t'] as Map)),
          );
        }
      } catch (e) {
        log.w('offline:73', e);
      }
    });
    // раньше разные треки с кириллицей могли получить одно имя файла — такие записи ненадёжны:
    // убрать их и сам файл (трек можно скачать заново)
    final byFile = <String, List<String>>{};
    _items.forEach((id, e) => byFile.putIfAbsent(e.$1, () => []).add(id));
    var dropped = false;
    for (final e in byFile.entries.where((e) => e.value.length > 1)) {
      for (final id in e.value) {
        _items.remove(id);
      }
      try {
        File('${d.path}/${e.key}').deleteSync();
      } catch (e) {
        log.w('offline:86', e);
      }
      dropped = true;
    }
    if (dropped) _saveIndex();
  }

  /// Запись индекса атомарно: сначала во временный файл, потом переименование — обрыв посередине
  /// (приложение закрыли во время загрузки) не оставляет пустой или обрезанный index.json.
  void _saveIndex([Map<String, (String, int, Track)>? entries]) {
    if (_dir == null) return;
    final tmp = File('${_dir!.path}/index.json.tmp');
    tmp.writeAsStringSync(
      jsonEncode({
        for (final e in (entries ?? _items).entries)
          e.key: {'f': e.value.$1, 'b': e.value.$2, 't': e.value.$3.toJson()},
      }),
      flush: true,
    );
    tmp.renameSync(_index.path);
  }

  bool has(Track t) => _items.containsKey(t.id);
  bool busy(Track t) => progress.containsKey(t.id) || _queue.contains(t);
  int get count => _items.length;
  int get bytes => _items.values.fold(0, (s, e) => s + e.$2);

  /// Только скачанное из сети (без своих файлов) — что удалит «Очистить загрузки».
  int get downloadedCount => _items.values.where((e) => !e.$3.isLocal).length;
  int get downloadedBytes => _items.values.where((e) => !e.$3.isLocal).fold(0, (s, e) => s + e.$2);

  /// Свои аудиофайлы.
  int get localCount => _items.values.where((e) => e.$3.isLocal).length;
  List<Track> get tracks => _items.values.map((e) => e.$3).toList().reversed.toList();

  /// Скачанное из сети (без своих файлов).
  List<Track> get downloaded => tracks.where((t) => !t.isLocal).toList();

  /// Свои аудиофайлы, добавленные с телефона.
  List<Track> get localTracks => tracks.where((t) => t.isLocal).toList();

  /// Добавить свои аудиофайлы: копия в папку приложения (играют без интернета, как скачанные).
  /// «Исполнитель - Название.mp3» → исполнитель и название, иначе название = имя файла.
  Future<List<Track>> importFiles(List<XFile> files) async {
    final d = await _folder();
    final out = <Track>[];
    for (final x in files) {
      final name = x.name;
      final dot = name.lastIndexOf('.');
      final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : 'mp3';
      final id = 'local:${DateTime.now().microsecondsSinceEpoch}';
      final fname = '${_safe(id)}.$ext';
      final dst = '${d.path}/$fname';
      await x.saveTo(dst);
      final t = _localTrack(id, name);
      _items[id] = (fname, File(dst).lengthSync(), t);
      out.add(t);
    }
    _saveIndex();
    notifyListeners();
    return out;
  }

  Future<({int added, int duplicates})> importZip(XFile file) async {
    final folder = await _folder();
    final temp = await getTemporaryDirectory();
    final staging = await temp.createTemp('echoes_zip_');
    final promoted = <File>[];
    try {
      final batch = await compute(unpackAudioZip, (file.path, staging.path));
      final changes = <String, (String, int, Track)>{};
      var duplicates = batch.duplicates;
      for (final audio in batch.tracks) {
        final id = 'local:zip-${audio.hash}';
        final track = _localTrack(
          id,
          audio.name,
          artist: audio.artist,
          title: audio.title,
          seconds: audio.seconds ?? 0,
        );
        if (fileFor(track) != null) {
          duplicates++;
          continue;
        }
        final name = 'zip-${audio.hash}.${audio.extension}';
        final dest = File(audio.path).renameSync('${folder.path}/$name');
        promoted.add(dest);
        changes[id] = (name, audio.bytes, track);
      }
      if (changes.isNotEmpty) {
        _saveIndex({..._items, ...changes});
        _items.addAll(changes);
        notifyListeners();
      }
      return (added: changes.length, duplicates: duplicates);
    } catch (_) {
      for (final file in promoted) {
        try {
          file.deleteSync();
        } on FileSystemException catch (e) {
          log.w('offline.zip.cleanup', e);
        }
      }
      rethrow;
    } finally {
      try {
        await staging.delete(recursive: true);
      } on FileSystemException catch (e) {
        log.w('offline.zip.staging', e);
      }
    }
  }

  Track _localTrack(String id, String name, {String? artist, String? title, int seconds = 0}) {
    final dot = name.lastIndexOf('.');
    final base = (dot > 0 ? name.substring(0, dot) : name).replaceAll('_', ' ').trim();
    final divider = base.indexOf(' - ');
    final filenameTitle = divider > 0 ? base.substring(divider + 3).trim() : base;
    return Track(
      id: id,
      title: title ?? (filenameTitle.isEmpty ? name : filenameTitle),
      artist: artist ?? (divider > 0 ? base.substring(0, divider).trim() : ''),
      seconds: seconds,
    );
  }

  /// Файл трека, если он скачан.
  File? fileFor(Track t) {
    final e = _items[t.id];
    if (e == null || _dir == null) return null;
    final f = File('${_dir!.path}/${e.$1}');
    return f.existsSync() ? f : null;
  }

  void download(Track t) => downloadAll([t]);

  void downloadAll(Iterable<Track> list) {
    for (final t in list) {
      if (has(t) || busy(t)) continue;
      failed.remove(t.id);
      _queue.add(t);
      progress[t.id] = 0;
    }
    notifyListeners();
    _pump();
  }

  void remove(Track t) {
    final f = fileFor(t);
    _items.remove(t.id);
    _queue.remove(t);
    progress.remove(t.id);
    try {
      f?.deleteSync();
    } catch (e) {
      log.w('offline:181', e);
    }
    _saveIndex();
    notifyListeners();
  }

  /// Удалить скачанное. Свои аудиофайлы остаются: их в сети нет, заново не скачать.
  Future<void> clear() async {
    _queue.clear();
    for (final t in downloaded) {
      remove(t);
    }
    // файлы-сироты (без записи в индексе) — тоже прочь; файлы оставшихся записей не трогаем
    final d = await _folder();
    final keep = {for (final e in _items.values) e.$1, 'index.json', 'index.json.broken'};
    for (final f in d.listSync().whereType<File>()) {
      if (!keep.contains(f.uri.pathSegments.last)) {
        try {
          f.deleteSync();
        } catch (e) {
          log.w('offline:199', e);
        }
      }
    }
    notifyListeners();
  }

  void _pump() {
    while (_running < _parallel && _queue.isNotEmpty) {
      final t = _queue.removeAt(0);
      _running++;
      _fetch(t).whenComplete(() {
        _running--;
        _pump();
      });
    }
  }

  DateTime _lastNotify = DateTime(0);
  void _tick(Track t, double p) {
    progress[t.id] = p;
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds > 250) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  static String _safe(String id) => safeName(id);

  /// Имя файла для трека. Латиница/цифры (id YouTube и т. п.) — как есть; иначе к «очищенному» имени
  /// добавляется хеш: «q:Кино — Пачка» и «q:Сплин — Мать» раньше оба превращались в «q_____________».
  /// Тем же способом называются файлы обложек и текстов песен.
  static String safeName(String id) {
    final ascii = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (ascii == id) return id;
    final head = ascii.length > 40 ? ascii.substring(0, 40) : ascii;
    return '${head}_${_hash(id)}';
  }

  /// FNV-1a (64 бита) от UTF-8 — 16 hex-символов.
  static String _hash(String s) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h *= 0x100000001b3;
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  Future<void> _fetch(Track t) async {
    final d = await _folder();
    final tmp = File('${d.path}/${_safe(t.id)}.part');
    try {
      final ext = await _download(t, tmp);
      final name = '${_safe(t.id)}.$ext';
      final f = tmp.renameSync('${d.path}/$name');
      _items[t.id] = (name, f.lengthSync(), t);
      _saveIndex();
    } catch (e) {
      failed[t.id] = '$e'.replaceFirst('Exception: ', '');
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (e) {
        log.w('offline:261', e);
      }
    } finally {
      progress.remove(t.id);
      notifyListeners();
    }
  }

  @visibleForTesting
  Future<String> downloadTo(Track t, File f) => _download(t, f);

  /// Скачать звук в tmp → расширение файла. Порядок как при игре: SoundCloud напрямую;
  /// иначе YouTube (у отрывков/импортированных — сначала найти видео), не вышло — та же песня на SoundCloud.
  Future<String> _download(Track t, File tmp) async {
    if (t.isSc) {
      try {
        return await _sc(await ScService.instance.track(t.scId), t, tmp);
      } catch (e) {
        // эта загрузка закрыта — другие копии той же песни на SoundCloud
        for (final m in (await ScService.instance.matches(t.artist, t.title, t.seconds, exclude: t.scId)).take(3)) {
          try {
            return await _sc(m, t, tmp);
          } catch (e) {
            log.w('offline:282', e);
          }
        }
        rethrow;
      }
    }
    final errs = <String>[];
    try {
      final vid = t.needsLookup ? await YtService.instance.findSame(t) : t.id;
      final pick = await YtService.instance.stream(vid);
      await _ranged(pick, t, tmp);
      return pick.mime.contains('video') ? 'mp4' : 'm4a';
    } catch (e) {
      errs.add('YouTube: $e');
    }
    try {
      final same = await ScService.instance.matches(t.artist, t.title, t.seconds);
      if (same.isEmpty) errs.add(tr('SoundCloud: такой песни нет'));
      Object? last;
      for (final m in same.take(4)) {
        try {
          return await _sc(m, t, tmp);
        } catch (e) {
          last = e;
        }
      }
      if (last != null) throw last;
    } catch (e) {
      errs.add('SoundCloud: $e');
    }
    throw Exception(errs.join(' · '));
  }

  /// YouTube притормаживает каждое соединение — качаем кусками по 1 МБ в 6 соединений сразу
  /// (в разы быстрее, чем по очереди) и пишем в файл по порядку.
  Future<void> _ranged(StreamPick pick, Track t, File tmp, {bool report = true}) async {
    const chunk = 1 << 20;
    final n = (pick.size + chunk - 1) ~/ chunk;
    final parts = List<List<int>?>.filled(n, null);
    var next = 0, written = 0, done = 0;
    var failed = false; // один кусок не скачался — остальные работники останавливаются (не копят МБ в памяти)
    final sink = tmp.openWrite();
    Future<List<int>> fetch(int i) async {
      final s = i * chunk;
      final e = ((i + 1) * chunk).clamp(0, pick.size) - 1;
      final want = e - s + 1;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          var r = await _client.get(pick.url, headers: {'Range': 'bytes=$s-$e'}).timeout(const Duration(seconds: 25));
          // сервер не выполнил Range (весь файл с начала) — запасной путь: параметр &range= в ссылке
          if ((r.statusCode != 206 && r.statusCode != 200) || r.bodyBytes.length != want) {
            r = await _client
                .get(pick.url.replace(queryParameters: {...pick.url.queryParameters, 'range': '$s-$e'}))
                .timeout(const Duration(seconds: 25));
          }
          if ((r.statusCode == 206 || r.statusCode == 200) && r.bodyBytes.length == want) return r.bodyBytes;
          if (attempt == 2) throw Exception('HTTP ${r.statusCode}, ${r.bodyBytes.length}/$want байт');
        } on TimeoutException {
          if (attempt == 2) rethrow;
        }
      }
      throw Exception('HTTP');
    }

    Future<void> worker() async {
      while (!failed) {
        final i = next++;
        if (i >= n) return;
        try {
          parts[i] = await fetch(i);
        } catch (_) {
          failed = true;
          rethrow;
        }
        if (failed) return;
        done++;
        if (report) _tick(t, done / n);
        // готовые куски — в файл по порядку, память не копится
        while (written < n && parts[written] != null) {
          sink.add(parts[written]!);
          parts[written] = null;
          written++;
        }
      }
    }

    try {
      await Future.wait([for (var k = 0; k < (n < 6 ? n : 6); k++) worker()]);
      if (written != n) throw Exception('не все части скачались');
    } finally {
      await sink.close();
    }
  }

  /// SoundCloud: обычный mp3 — одним файлом; HLS — сегменты подряд (mp3-куски или fMP4 с init-сегментом).
  Future<String> _sc(ScTrack st, Track t, File tmp) async => _fetchUrl(await ScService.instance.streamUrl(st), t, tmp);

  /// Скачать по ссылке SoundCloud: обычный mp3 — потоком, HLS — сегменты подряд.
  Future<String> _fetchUrl(Uri u, Track t, File tmp, {bool report = true}) async {
    if (!u.path.contains('.m3u8') && !u.toString().contains('playlist.m3u8')) {
      final r = await _client.send(http.Request('GET', u)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        await r.stream.drain<void>();
        throw Exception('SoundCloud: HTTP ${r.statusCode}');
      }
      final total = r.contentLength ?? 0;
      var got = 0;
      final sink = tmp.openWrite();
      try {
        await for (final b in r.stream.timeout(const Duration(seconds: 20))) {
          sink.add(b);
          got += b.length;
          if (total > 0 && report) _tick(t, got / total);
        }
      } finally {
        await sink.close();
      }
      return (r.headers['content-type'] ?? '').contains('mp4') ? 'm4a' : 'mp3';
    }
    final list = await http.get(u).timeout(const Duration(seconds: 15));
    final lines = const LineSplitter().convert(list.body);
    final segs = <Uri>[];
    var mp4 = false;
    for (final l in lines) {
      final m = RegExp(r'#EXT-X-MAP:URI="([^"]+)"').firstMatch(l);
      if (m != null) {
        segs.insert(0, u.resolve(m.group(1)!));
        mp4 = true;
      } else if (l.isNotEmpty && !l.startsWith('#')) {
        segs.add(u.resolve(l.trim()));
      }
    }
    if (segs.isEmpty) throw Exception(tr('SoundCloud: пустой HLS'));
    // сегменты HLS — в 6 соединений сразу, в файл — по порядку
    final sink = tmp.openWrite();
    final got = List<List<int>?>.filled(segs.length, null);
    var next = 0, written = 0, done = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= segs.length) return;
        final r = await _client.get(segs[i]).timeout(const Duration(seconds: 25));
        if (r.statusCode != 200) throw Exception('SoundCloud: HTTP ${r.statusCode}');
        got[i] = r.bodyBytes;
        done++;
        if (report) _tick(t, done / segs.length);
        while (written < segs.length && got[written] != null) {
          sink.add(got[written]!);
          got[written] = null;
          written++;
        }
      }
    }

    try {
      await Future.wait([for (var k = 0; k < 6; k++) worker()]);
    } finally {
      await sink.close();
    }
    return mp4 || segs.first.path.contains('.m4s') ? 'm4a' : 'mp3';
  }
}

extension PlaybackCache on Offline {
  /// Запасной путь для игры: плеер iOS не открыл ссылку (бывает «unsupported URL», а после фона —
  /// «не удалось подключиться» к его внутреннему прокси) — быстро качаем трек во временный кэш
  /// (Caches, iOS чистит его сам; держим последние 25) и играем из файла.
  /// Временные файлы, которые качаются прямо сейчас: тот же трек из того же источника — один общий
  /// Future (повторный запрос ждёт его, а не пишет в тот же файл параллельно).
  static final _playing = <String, Future<File>>{};

  Future<File> playbackFile(Track t, {Uri? url, StreamPick? pick}) {
    final key = '${t.id}|${pick != null ? 'yt:${pick.url}' : '$url'}';
    final run = _playing[key];
    if (run != null) return run;
    final f = _playbackFile(t, url: url, pick: pick);
    _playing[key] = f;
    return f.whenComplete(() => _playing.remove(key));
  }

  static int _partSeq = 0;

  Future<File> _playbackFile(Track t, {Uri? url, StreamPick? pick}) async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/echoes_play');
    if (!d.existsSync()) d.createSync(recursive: true);
    final name = Offline._safe(t.id);
    for (final f in d.listSync().whereType<File>()) {
      if (f.uri.pathSegments.last.startsWith('$name.') && !f.path.endsWith('.part')) return f;
    }
    // своё имя у каждой загрузки: разные источники одного трека не портят байты друг другу
    final tmp = File('${d.path}/$name.${DateTime.now().microsecondsSinceEpoch}-${_partSeq++}.part');
    String ext;
    try {
      if (pick != null) {
        await _ranged(pick, t, tmp, report: false);
        ext = pick.mime.contains('video') ? 'mp4' : 'm4a';
      } else {
        ext = await _fetchUrl(url!, t, tmp, report: false);
      }
    } catch (_) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (e) {
        log.w('offline:475', e);
      }
      rethrow;
    }
    final out = tmp.renameSync('${d.path}/$name.$ext');
    // старые — прочь (недокачанные .part не трогаем: их ещё пишут)
    final all = d.listSync().whereType<File>().where((f) => !f.path.endsWith('.part')).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final f in all.skip(25)) {
      try {
        f.deleteSync();
      } catch (e) {
        log.w('offline:485', e);
      }
    }
    return out;
  }
}

String fmtBytes(int b) {
  if (b >= 1 << 30) return tr('{0} ГБ', [(b / (1 << 30)).toStringAsFixed(1)]);
  if (b >= 1 << 20) return tr('{0} МБ', [(b / (1 << 20)).toStringAsFixed(b >= 100 << 20 ? 0 : 1)]);
  return tr('{0} КБ', [(b / 1024).ceil()]);
}
