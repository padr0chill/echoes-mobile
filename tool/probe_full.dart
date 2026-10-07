// ignore_for_file: avoid_print
// Какие клиенты отдают ВЕСЬ файл (кусок из середины и из конца), а не только начало.
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final id = args.isNotEmpty ? args.first : 'x1ZtIVuHph0';
  final yt = YoutubeExplode();
  for (final e in <String, List<YoutubeApiClient>?>{
    'android': [YoutubeApiClient.android],
    'default': null,
    'ios': [YoutubeApiClient.ios],
    'androidVr': [YoutubeApiClient.androidVr],
    'tv': [YoutubeApiClient.tv],
    'mweb': [YoutubeApiClient.mweb],
  }.entries) {
    try {
      final m = e.value == null
          ? await yt.videos.streamsClient.getManifest(id).timeout(const Duration(seconds: 20))
          : await yt.videos.streamsClient.getManifest(id, ytClients: e.value).timeout(const Duration(seconds: 20));
      final a = m.audioOnly.toList()..sort((x, y) => x.bitrate.compareTo(y.bitrate));
      for (final s in a) {
        final size = s.size.totalBytes;
        final mid = size ~/ 2;
        Future<int> h(int from, int to) async =>
            (await http.get(s.url, headers: {'Range': 'bytes=$from-$to'}).timeout(const Duration(seconds: 15))).statusCode;
        Future<int> p(int from, int to) async => (await http
                .get(s.url.replace(queryParameters: {...s.url.queryParameters, 'range': '$from-$to'}))
                .timeout(const Duration(seconds: 15)))
            .statusCode;
        print('${e.key} itag ${s.tag} ${s.container.name} c=${s.url.queryParameters['c']}: '
            'hdr start ${await h(0, 65535)} mid ${await h(mid, mid + 65535)} end ${await h(size - 1000, size - 1)} | '
            'param mid ${await p(mid, mid + 65535)}');
      }
    } catch (err) {
      print('${e.key}: FAIL ${'$err'.split('\n').first}');
    }
  }
  yt.close();
}
