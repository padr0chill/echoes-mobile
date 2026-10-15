// Живая проверка клипов: находится ли официальное видео и отдаёт ли YouTube его целиком.
@Tags(['network'])
library;

import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/clips.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  for (final t in const [
    Track(id: 'a', title: 'Numb', artist: 'Linkin Park', seconds: 187),
    Track(id: 'b', title: 'Kosandra', artist: 'Miyagi & Andy Panda', seconds: 221),
    Track(id: 'c', title: 'METAMORPHOSIS 3', artist: 'INTERWORLD', seconds: 128),
    Track(id: 'd', title: 'где', artist: 'zxcursed', seconds: 106),
  ]) {
    test('${t.artist} — ${t.title}', () async {
      final c = await Clips.instance.find(t);
      // ignore: avoid_print
      print('${t.title}: ${c == null ? 'клипа нет' : '${c.title} | ${c.channel} | ${c.seconds}s | ${c.id}'}');
      if (c == null) return;
      final u = await Clips.instance.streamUrl(c.id);
      final r = await http.get(u, headers: {'Range': 'bytes=1500000-1500999'});
      // ignore: avoid_print
      print('  прокси: $u → HTTP ${r.statusCode}, ${r.bodyBytes.length} байт, ${r.headers['content-type']}');
      expect(r.statusCode, 206);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
