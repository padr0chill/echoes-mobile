import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'sc.dart';
import 'yt.dart';
import '../i18n.dart';

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
  static const _parallel = 2;
  final _client = http.Client();

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/offline');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _dir = d;
  }

  File get _index => File('${_dir!.path}/index.json');

  Future<void> load() async {
    try {
      await _folder();
      if (!_index.existsSync()) return;
      final j = jsonDecode(_index.readAsStringSync()) as Map;
      j.forEach((id, v) {
        final m = v as Map;
        final f = File('${_dir!.path}/${m['f']}');
        if (f.existsSync()) {
          _items['$id'] = (
            '${m['f']}',
            (m['b'] as num).toInt(),
            Track.fromJson(Map<String, dynamic>.from(m['t'] as Map)),
          );
        }
      });
    } catch (_) {}
  }

  void _saveIndex() {
    if (_dir == null) return;
    _index.writeAsStringSync(jsonEncode({
      for (final e in _items.entries) e.key: {'f': e.value.$1, 'b': e.value.$2, 't': e.value.$3.toJson()},
    }));
  }

  bool has(Track t) => _items.containsKey(t.id);
  bool busy(Track t) => progress.containsKey(t.id) || _queue.contains(t);
  int get count => _items.length;
  int get bytes => _items.values.fold(0, (s, e) => s + e.$2);
  List<Track> get tracks => _items.values.map((e) => e.$3).toList().reversed.toList();

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
    } catch (_) {}
    _saveIndex();
    notifyListeners();
  }

  Future<void> clear() async {
    _queue.clear();
    for (final t in tracks) {
      remove(t);
    }
    final d = await _folder();
    for (final f in d.listSync()) {
      if (f is File && !f.path.endsWith('index.json')) {
        try {
          f.deleteSync();
        } catch (_) {}
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

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

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
      } catch (_) {}
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
    if (t.isSc) return _sc(await ScService.instance.track(t.scId), t, tmp);
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
      final same = await ScService.instance.match(t.artist, t.title, t.seconds);
      if (same != null) return await _sc(same, t, tmp);
      errs.add(tr('SoundCloud: такой песни нет'));
    } catch (e) {
      errs.add('SoundCloud: $e');
    }
    throw Exception(errs.join(' · '));
  }

  /// YouTube отдаёт файл только кусками (Range) — качаем по 1 МБ.
  Future<void> _ranged(StreamPick pick, Track t, File tmp, {bool report = true}) async {
    final sink = tmp.openWrite();
    try {
      const chunk = 1 << 20;
      for (var s = 0; s < pick.size; s += chunk) {
        final e = (s + chunk).clamp(0, pick.size) - 1;
        var r = await _client.send(http.Request('GET', pick.url)..headers['Range'] = 'bytes=$s-$e');
        if (r.statusCode != 206 && r.statusCode != 200) {
          await r.stream.drain<void>();
          r = await _client.send(
              http.Request('GET', pick.url.replace(queryParameters: {...pick.url.queryParameters, 'range': '$s-$e'})));
        }
        if (r.statusCode != 206 && r.statusCode != 200) {
          await r.stream.drain<void>();
          throw Exception('HTTP ${r.statusCode}');
        }
        await sink.addStream(r.stream);
        if (report) _tick(t, (e + 1) / pick.size);
      }
    } finally {
      await sink.close();
    }
  }

  /// SoundCloud: обычный mp3 — одним файлом; HLS — сегменты подряд (mp3-куски или fMP4 с init-сегментом).
  Future<String> _sc(ScTrack st, Track t, File tmp) async => _fetchUrl(await ScService.instance.streamUrl(st), t, tmp);

  /// Скачать по ссылке SoundCloud: обычный mp3 — потоком, HLS — сегменты подряд.
  Future<String> _fetchUrl(Uri u, Track t, File tmp, {bool report = true}) async {
    if (!u.path.contains('.m3u8') && !u.toString().contains('playlist.m3u8')) {
      final r = await _client.send(http.Request('GET', u));
      if (r.statusCode != 200) {
        await r.stream.drain<void>();
        throw Exception('SoundCloud: HTTP ${r.statusCode}');
      }
      final total = r.contentLength ?? 0;
      var got = 0;
      final sink = tmp.openWrite();
      try {
        await for (final b in r.stream) {
          sink.add(b);
          got += b.length;
          if (total > 0 && report) _tick(t, got / total);
        }
      } finally {
        await sink.close();
      }
      return (r.headers['content-type'] ?? '').contains('mp4') ? 'm4a' : 'mp3';
    }
    final list = await http.get(u);
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
    final sink = tmp.openWrite();
    try {
      for (var i = 0; i < segs.length; i++) {
        final r = await _client.get(segs[i]);
        if (r.statusCode != 200) throw Exception('SoundCloud: HTTP ${r.statusCode}');
        sink.add(r.bodyBytes);
        if (report) _tick(t, (i + 1) / segs.length);
      }
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
  Future<File> playbackFile(Track t, {Uri? url, StreamPick? pick}) async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/echoes_play');
    if (!d.existsSync()) d.createSync(recursive: true);
    final name = Offline._safe(t.id);
    for (final f in d.listSync().whereType<File>()) {
      if (f.uri.pathSegments.last.startsWith('$name.') && !f.path.endsWith('.part')) return f;
    }
    final tmp = File('${d.path}/$name.part');
    String ext;
    if (pick != null) {
      await _ranged(pick, t, tmp, report: false);
      ext = pick.mime.contains('video') ? 'mp4' : 'm4a';
    } else {
      ext = await _fetchUrl(url!, t, tmp, report: false);
    }
    final out = tmp.renameSync('${d.path}/$name.$ext');
    // старые — прочь
    final all = d.listSync().whereType<File>().toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final f in all.skip(25)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    return out;
  }
}

String fmtBytes(int b) {
  if (b >= 1 << 30) return tr('{0} ГБ', [(b / (1 << 30)).toStringAsFixed(1)]);
  if (b >= 1 << 20) return tr('{0} МБ', [(b / (1 << 20)).toStringAsFixed(b >= 100 << 20 ? 0 : 1)]);
  return tr('{0} КБ', [(b / 1024).ceil()]);
}
