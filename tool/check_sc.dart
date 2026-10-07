// ignore_for_file: avoid_print
// SoundCloud как запасной источник: client_id, поиск той же песни, ссылка на звук, кусок из середины.
import 'package:echoes_mobile/services/sc.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final sw = Stopwatch()..start();
  final cid = await ScService.instance.clientId();
  print('client_id ok (${cid.length} chars) in ${sw.elapsedMilliseconds} ms');
  for (final q in [
    ['xCharnee', 'Cursed World 1.1', 83],
    ['Linkin Park', 'Numb', 186],
    ['Miyagi & Andy Panda', 'Kosandra', 221],
  ]) {
    sw.reset();
    try {
      final u = await ScService.instance.findSame(q[0] as String, q[1] as String, q[2] as int);
      if (u == null) {
        print('${q[1]}: no match (${sw.elapsedMilliseconds} ms)');
        continue;
      }
      final isHls = u.path.endsWith('.m3u8') || u.toString().contains('playlist');
      final r = await http.get(u, headers: isHls ? {} : {'Range': 'bytes=200000-201023'});
      print(
          '${q[1]}: ${isHls ? 'HLS' : 'progressive'} -> HTTP ${r.statusCode} ${r.headers['content-type']} (${sw.elapsedMilliseconds} ms)');
    } catch (e) {
      print('${q[1]}: FAIL $e');
    }
  }
}
