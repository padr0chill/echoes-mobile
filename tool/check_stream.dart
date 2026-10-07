// ignore_for_file: avoid_print
// Проверка без телефона: поиск, аудиопоток (AAC для iOS) и текст песни.
// Запуск: dart run tool/check_stream.dart "запрос"
import 'package:echoes_mobile/services/lyrics.dart';
import 'package:echoes_mobile/services/yt.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final q = args.isNotEmpty ? args.join(' ') : 'Linkin Park Numb';
  final sw = Stopwatch()..start();
  final res = await YtService.instance.search(q);
  print('search "$q": ${res.length} results in ${sw.elapsedMilliseconds} ms');
  for (final t in res.take(3)) {
    print('  ${t.artist} — ${t.title} (${t.seconds}s) ${t.id}');
  }
  if (res.isEmpty) return;
  final t = res.first;
  sw.reset();
  final url = await YtService.instance.streamUrl(t.id);
  print(
      'stream url in ${sw.elapsedMilliseconds} ms: ${url.host} mime=${url.queryParameters['mime']} itag=${url.queryParameters['itag']}');
  final r = await http.get(url, headers: {'Range': 'bytes=0-65535'});
  print('range request: HTTP ${r.statusCode}, ${r.bodyBytes.length} bytes, type=${r.headers['content-type']}');
  final eco = await YtService.instance.streamUrl(t.id, economy: true);
  print('economy itag=${eco.queryParameters['itag']}');
  final ly = await LyricsService.instance.get(t);
  print('lyrics: ${ly == null ? 'none' : '${ly.lines.length} lines, synced=${ly.synced}'}');
}
