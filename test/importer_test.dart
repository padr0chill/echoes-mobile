import 'dart:convert';

import 'package:echoes_mobile/services/importer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Импорт плейлистов: .m3u, список строк .txt и файлы ECHOES с ПК.
void main() {
  test('m3u: название и длительность из #EXTINF, путь к файлу пропускается', () {
    final lists = Importer.parse('''#EXTM3U
#EXTINF:215,Кино - Пачка сигарет
C:\\Music\\kino.mp3
#EXTINF:180,Сплин – Мое сердце
/music/splin.mp3
''');
    final t = lists.single.$2;
    expect(t.map((x) => x.title), ['Пачка сигарет', 'Мое сердце']);
    expect(t.map((x) => x.artist), ['Кино', 'Сплин']);
    expect(t.first.seconds, 215);
  });

  test('txt: нумерация и длительность в скобках', () {
    final t = Importer.parse('1. Daft Punk - One More Time (5:20)\n2) Moby — Porcelain\n').single.$2;
    expect(t.map((x) => x.title), ['One More Time', 'Porcelain']);
    expect(t.first.seconds, 320);
  });

  test('пустой файл — понятная ошибка', () {
    expect(() => Importer.parse('#EXTM3U\n\n'), throwsFormatException);
  });

  test('T33: id YouTube из файла — только настоящие 11 символов, «../» не проходит', () {
    final raw = jsonEncode({
      'format': 'echoes-playlist',
      'name': 'P',
      'tracks': [
        {'id': 'yt:dQw4w9WgXcQ', 'title': 'Never', 'artist': 'Rick'},
        {'id': 'yt:../../../ab', 'title': 'Evil', 'artist': 'X'},
      ],
    });
    final t = Importer.parse(raw).single.$2;
    expect(t[0].id, 'dQw4w9WgXcQ');
    expect(t[1].id, startsWith('q:')); // не путь, а поиск по названию
  });
}
