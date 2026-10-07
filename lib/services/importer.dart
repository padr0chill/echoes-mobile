import 'dart:convert';

import '../models.dart';
import 'sc.dart';

/// Плейлист из файла: название и треки.
typedef ImportedList = (String, List<Track>);

/// Файлы плейлистов с ПК-версии ECHOES:
///  * «.echoesplaylist» — один плейлист (format «echoes-playlist») или все сразу («echoes-playlists»);
///    у трека может быть id: «yt:<видео>» или «sc:<трек SoundCloud>» — тогда играет именно эта запись;
///  * .m3u / .txt — строки «Исполнитель - Название»: звук ищется по названию.
class Importer {
  Importer._();

  static List<ImportedList> parse(String raw, {String fallbackName = 'С компьютера'}) {
    raw = raw.replaceFirst('﻿', '');
    if (raw.trimLeft().startsWith('{')) {
      final d = jsonDecode(raw) as Map;
      final f = d['format'];
      if (f == 'echoes-playlists') {
        return [for (final p in (d['playlists'] as List? ?? []).cast<Map>()) _one(p, fallbackName)];
      }
      if (f == 'echoes-playlist') return [_one(d, fallbackName)];
      throw const FormatException('это не плейлист ECHOES');
    }
    final out = <Track>[];
    int? extDur;
    for (var line in const LineSplitter().convert(raw)) {
      line = line.trim();
      if (line.toUpperCase().startsWith('#EXTINF')) {
        final body = line.contains(':') ? line.substring(line.indexOf(':') + 1) : '';
        extDur = int.tryParse(body.split(',').first.trim());
        final rest = body.contains(',') ? body.substring(body.indexOf(',') + 1) : '';
        final t = _line(rest, extDur ?? 0);
        if (t != null) out.add(t);
        continue;
      }
      if (line.isEmpty || line.startsWith('#')) continue;
      if (extDur != null) {
        extDur = null; // путь к файлу после #EXTINF — трек уже добавлен
        continue;
      }
      final t = _line(line, 0);
      if (t != null) out.add(t);
    }
    if (out.isEmpty) throw const FormatException('в файле не нашлось ни одного трека');
    return [(fallbackName, out)];
  }

  static ImportedList _one(Map p, String fallbackName) {
    final tracks = <Track>[];
    for (final t in (p['tracks'] as List? ?? []).cast<Map>()) {
      final title = '${t['title'] ?? ''}'.trim();
      if (title.isEmpty) continue;
      final artist = '${t['artist'] ?? ''}'.trim();
      final s = ((t['duration'] ?? 0) as num).round();
      final ref = '${t['id'] ?? ''}';
      final id = ref.startsWith('yt:') && ref.length == 14
          ? ref.substring(3)
          : ref.startsWith('sc:') && int.tryParse(ref.substring(3)) != null
              ? ref
              : 'q:$artist — $title';
      tracks.add(Track(id: id, title: title, artist: artist, seconds: s));
    }
    final name = '${p['name'] ?? ''}'.trim();
    return (name.isEmpty ? fallbackName : name, tracks);
  }

  static Track? _line(String s, int dur) {
    s = s.trim().replaceFirst(RegExp(r'^\d+[.)]\s+'), '');
    final m = RegExp(r'[\(\[]\s*(\d{1,2}):(\d{2})\s*[\)\]]\s*$').firstMatch(s);
    if (m != null) {
      dur = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
      s = s.substring(0, m.start).trim();
    }
    // путь к файлу → имя без расширения
    if (s.contains('/') || s.contains(r'\')) s = s.split(RegExp(r'[/\\]')).last.replaceFirst(RegExp(r'\.\w{2,4}$'), '');
    if (s.isEmpty) return null;
    for (final sep in const [' — ', ' – ', ' - ']) {
      final i = s.indexOf(sep);
      if (i > 0) {
        final a = s.substring(0, i).trim(), t = s.substring(i + sep.length).trim();
        return Track(id: 'q:$a — $t', title: t, artist: a, seconds: dur);
      }
    }
    return Track(id: 'q:$s', title: s, artist: '', seconds: dur);
  }

  /// Треки SoundCloud — сведения из SoundCloud (обложка, исполнитель, отрывок ли); удалённые — искать по названию.
  static Future<List<ImportedList>> resolve(List<ImportedList> lists) async {
    final ids = <int>{
      for (final (_, ts) in lists)
        for (final t in ts)
          if (t.isSc) t.scId,
    }.toList();
    Map<int, Track> found = {};
    if (ids.isNotEmpty) {
      try {
        found = await ScService.instance.tracksByIds(ids);
      } catch (_) {
        return lists; // нет сети к SoundCloud — оставим как есть, сведения подтянутся при игре
      }
    }
    return [
      for (final (name, ts) in lists)
        (
          name,
          [
            for (final t in ts)
              if (!t.isSc)
                t
              else if (found[t.scId] != null)
                found[t.scId]!
              else
                Track(id: 'q:${t.artist} — ${t.title}', title: t.title, artist: t.artist, seconds: t.seconds),
          ]
        ),
    ];
  }
}
