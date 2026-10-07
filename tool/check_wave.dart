// ignore_for_file: avoid_print
// Цепочка волны: трек → та же песня на SoundCloud → похожие → звук похожего; плюс подбор замены.
import 'package:echoes_mobile/services/sc.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final sc = ScService.instance;
  final cases = [
    ['xCharnee', 'Cursed World 1.1', 83],
    ['Miyagi & Andy Panda', 'Kosandra', 221],
    ['N0IR', 'Иуда', 90],
    ['The Weeknd', 'Blinding Lights', 200],
    ['Linkin Park', 'Numb', 186],
    ['Kai Angel', 'Hlwn', 0],
    ['zxcursed', 'blessed', 124],
  ];
  var found = 0;
  for (final c in cases) {
    final sw = Stopwatch()..start();
    final m = await sc.match(c[0] as String, c[1] as String, c[2] as int);
    if (m != null) found++;
    print('match "${c[0]} - ${c[1]}": ${m == null ? 'НЕТ' : '${m.artist} — ${m.title} (${m.seconds}s)'} ${sw.elapsedMilliseconds}ms');
  }
  print('найдено $found из ${cases.length}');
  final seed = await sc.match('Linkin Park', 'Numb', 186);
  final rel = await sc.related(seed!.id);
  print('related: ${rel.length}; first: ${rel.take(3).map((t) => '${t.artist} — ${t.title}').join(' | ')}');
  final st = await sc.track(rel.first.scId);
  final u = await sc.streamUrl(st);
  final r = await http.get(u, headers: {'Range': 'bytes=100000-101023'});
  print('related #1 stream: HTTP ${r.statusCode} ${r.headers['content-type']}');
  final s = await sc.searchTracks('phonk');
  print('searchTracks phonk: ${s.length}');
}
