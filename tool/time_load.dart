// ignore_for_file: avoid_print
import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/sc.dart';
import 'package:echoes_mobile/services/yt.dart';
import 'package:http/http.dart' as http;

/// Сколько времени занимает каждый этап открытия трека (без плеера): dart run tool/time_load.dart
Future<void> main() async {
  final sw = Stopwatch()..start();
  int lap() {
    final v = sw.elapsedMilliseconds;
    sw.reset();
    return v;
  }

  await ScService.instance.clientId();
  print('SoundCloud client_id (холодный старт): ${lap()} мс');

  final sc = await ScService.instance.searchTracks('zxcursed blessed');
  lap();
  final st = await ScService.instance.track(sc.first.scId);
  print('SC track(): ${lap()} мс (из кэша поиска)');
  final u = await ScService.instance.streamUrl(st);
  print('SC streamUrl(): ${lap()} мс');
  final r = await http.get(u, headers: {'Range': 'bytes=0-65535'});
  print('SC первые 64 КБ: ${lap()} мс (${r.statusCode})');

  for (final t in const [
    Track(id: 'HbkC9qHA6wU', title: 'Kosandra', artist: 'Miyagi & Andy Panda', seconds: 222),
    Track(id: 'eHECKcnloCE', title: 'Papercut', artist: 'Linkin Park', seconds: 185),
  ]) {
    print('\n${t.artist} — ${t.title}');
    for (var i = 0; i < 2; i++) {
      lap();
      try {
        final p = await YtService.instance.streamWith(t.id, i);
        print('  YouTube#$i: ${lap()} мс (${p.mime}, ${(p.size / 1048576).toStringAsFixed(1)} МБ)');
        final rr = await http.get(p.url, headers: {'Range': 'bytes=0-65535'});
        print('  первые 64 КБ: ${lap()} мс (${rr.statusCode})');
      } catch (e) {
        print('  YouTube#$i: ошибка за ${lap()} мс: $e');
      }
    }
    lap();
    final m = await ScService.instance.match(t.artist, t.title, t.seconds);
    print('  SC match: ${lap()} мс → ${m == null ? 'нет' : '${m.artist} — ${m.title}'}');
    if (m != null) {
      await ScService.instance.streamUrl(m);
      print('  SC streamUrl: ${lap()} мс');
    }
  }
}
