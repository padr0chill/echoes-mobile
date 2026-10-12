// Проверка потоков с компьютера: какие способы YouTube и SoundCloud сейчас отдают звук.
// flutter test test/stream_probe_test.dart --run-skipped   (запрос — переменная окружения Q)
@Tags(['network'])
library;

import 'dart:io';

import 'package:echoes_mobile/services/sc.dart';
import 'package:echoes_mobile/services/yt.dart';
import 'package:echoes_mobile/services/ytm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('какие способы дают поток', () async {
    final q = Platform.environment['Q'] ?? 'zxcursed где';
    final ytm = await YtmService.instance.searchSongs(q, limit: 3);
    final yt = await YtService.instance.search(q);
    final ids = {...ytm.map((t) => t.id), ...yt.take(2).map((t) => t.id)};
    for (final t in [...ytm, ...yt.take(2)]) {
      // ignore: avoid_print
      print('найдено: ${t.artist} — ${t.title} ${t.id}');
    }
    for (final id in ids) {
      for (var i = 0; i < YtService.clients.length; i++) {
        final sw = Stopwatch()..start();
        try {
          final p = await YtService.instance.streamWith(id, i, fresh: true);
          // ignore: avoid_print
          print('$id client $i: OK ${p.mime} ${p.size} байт за ${sw.elapsedMilliseconds} мс');
        } catch (e) {
          // ignore: avoid_print
          print('$id client $i: ОШИБКА ${'$e'.split('\n').first} (${sw.elapsedMilliseconds} мс)');
        }
      }
    }
    final sc = await ScService.instance.search(q);
    for (final t in sc.take(3)) {
      try {
        final u = await ScService.instance.streamUrl(t);
        final kinds = t.transcodings
            .map((x) => '${(x['format'] as Map?)?['protocol']}/${(x['format'] as Map?)?['mime_type']}')
            .join(', ');
        // ignore: avoid_print
        print('  форматы: $kinds');
        // ignore: avoid_print
        print('SC ${t.artist} — ${t.title}: OK ${u.host}');
      } catch (e) {
        // ignore: avoid_print
        print(
            'SC ${t.artist} — ${t.title}: ОШИБКА $e  форматы: ${t.transcodings.map((x) => '${(x['format'] as Map?)?['protocol']}/${(x['format'] as Map?)?['mime_type']}').join(', ')}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
