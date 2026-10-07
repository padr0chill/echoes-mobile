// ignore_for_file: avoid_print
// Один ролик: каждый клиент → ссылка → ответ на запрос куска заголовком Range и параметром &range=.
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final id = args.isNotEmpty ? args.first : 'kXYiU_JCYtU';
  final yt = YoutubeExplode();
  for (final e in <String, List<YoutubeApiClient>?>{
    'android': [YoutubeApiClient.android],
    'default': null,
  }.entries) {
    try {
      final m = e.value == null
          ? await yt.videos.streamsClient.getManifest(id)
          : await yt.videos.streamsClient.getManifest(id, ytClients: e.value);
      for (final s in m.audioOnly.where((s) => s.container == StreamContainer.mp4)) {
        final h = await http.get(s.url, headers: {'Range': 'bytes=0-65535'}).timeout(const Duration(seconds: 15));
        final p = await http.get(s.url.replace(queryParameters: {...s.url.queryParameters, 'range': '0-65535'})).timeout(const Duration(seconds: 15));
        const full = '-';
        print('${e.key} itag ${s.tag} c=${s.url.queryParameters['c']}: header ${h.statusCode}, param ${p.statusCode}, explode.get chunks $full');
      }
    } catch (err) {
      print('${e.key}: FAIL ${'$err'.split('\n').first}');
    }
  }
  yt.close();
}
