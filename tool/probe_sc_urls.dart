// ignore_for_file: avoid_print
import 'package:echoes_mobile/services/sc.dart';
Future<void> main() async {
  for (final q in ['lil flash sex', 'rim0 toxic', 'onyx dio умру молодой', 'atl swae shii crazy', 'kai angel leopard red']) {
    final r = await ScService.instance.search(q, limit: 3);
    for (final t in r.where((t) => t.playable).take(1)) {
      final kinds = t.transcodings.map((x) => '${(x['format'] as Map)['protocol']}:${(x['format'] as Map)['mime_type']}').join(', ');
      final u = await ScService.instance.streamUrl(t);
      print('${t.artist} — ${t.title}\n   [$kinds]\n   → ${u.toString().substring(0, u.toString().length.clamp(0, 140))}');
    }
  }
}
