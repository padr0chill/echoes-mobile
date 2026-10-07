// ignore_for_file: avoid_print
import 'package:echoes_mobile/services/sc.dart';
import 'package:http/http.dart' as http;
Future<void> main() async {
  final r = await ScService.instance.search('zxcursed mana break', limit: 5);
  for (final t in r.take(3)) {
    print('${t.id} ${t.artist} — ${t.title} ${t.seconds}s playable=${t.playable} snippet=${t.snippet}');
    for (final x in t.transcodings) {
      final f = x['format'] as Map;
      print('   ${f['protocol']} ${f['mime_type']}');
    }
    try {
      final u = await ScService.instance.streamUrl(t);
      final h = await http.get(u, headers: {'Range': 'bytes=0-15'});
      print('   → ${u.host}${u.path.substring(0, u.path.length.clamp(0, 50))} HTTP ${h.statusCode} ${h.headers['content-type']}');
    } catch (e) {
      print('   → ERR $e');
    }
  }
}
