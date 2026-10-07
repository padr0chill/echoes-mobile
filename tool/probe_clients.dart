// ignore_for_file: avoid_print
// Какие клиенты YouTube сейчас дают рабочие ссылки на аудио (Range-запрос → 206).
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final yt = YoutubeExplode();
  final ids = args.isNotEmpty ? args : ['8P0vKLHbtMg', 'x1ZtIVuHph0'];
  final clients = <String, List<YoutubeApiClient>?>{
    'default': null,
    'ios': [YoutubeApiClient.ios],
    'androidVr': [YoutubeApiClient.androidVr],
    'tv': [YoutubeApiClient.tv],
    'safari': [YoutubeApiClient.safari],
    'mweb': [YoutubeApiClient.mweb],
    'android': [YoutubeApiClient.android],
    'mediaConnect': [YoutubeApiClient.mediaConnect],
  };
  for (final id in ids) {
    for (final e in clients.entries) {
      final sw = Stopwatch()..start();
      try {
        final m = e.value == null
            ? await yt.videos.streamsClient.getManifest(id)
            : await yt.videos.streamsClient.getManifest(id, ytClients: e.value);
        final a = m.audioOnly.where((s) => s.container == StreamContainer.mp4).toList()
          ..sort((x, y) => x.bitrate.compareTo(y.bitrate));
        if (a.isEmpty) {
          print('$id ${e.key}: no mp4 audio (${sw.elapsedMilliseconds} ms)');
          continue;
        }
        final s = a.last;
        final r = await http.get(s.url, headers: {'Range': 'bytes=0-65535'});
        final r2 = await http.get(s.url, headers: {
          'Range': 'bytes=0-65535',
          'User-Agent': 'AppleCoreMedia/1.0.0.21E236 (iPhone; U; CPU OS 17_4 like Mac OS X; en_us)'
        });
        print('$id ${e.key}: itag ${s.tag} -> HTTP ${r.statusCode} / ios-UA ${r2.statusCode} (${sw.elapsedMilliseconds} ms) c=${s.url.queryParameters['c']}');
      } catch (err) {
        print('$id ${e.key}: FAIL ${'$err'.split('\n').first} (${sw.elapsedMilliseconds} ms)');
      }
    }
  }
  yt.close();
}
