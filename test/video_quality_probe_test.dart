// Какие качества видео YouTube отдаёт целиком (а не только первый мегабайт).
@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('качества', () async {
    final yt = YoutubeExplode();
    final m = await yt.videos.streamsClient.getManifest('kXYiU_JCYtU', ytClients: [YoutubeApiClient.android]);
    Future<String> tail(StreamInfo s) async {
      final n = s.size.totalBytes;
      final r = await http.get(s.url, headers: {'Range': 'bytes=${n - 2}-${n - 1}'});
      final mid = await http.get(s.url, headers: {'Range': 'bytes=${n ~/ 2}-${n ~/ 2 + 1}'});
      return 'конец ${r.statusCode}, середина ${mid.statusCode}';
    }

    for (final s in m.muxed) {
      // ignore: avoid_print
      print(
          'muxed ${s.tag} ${s.videoResolution} ${s.container} ${(s.size.totalMegaBytes).toStringAsFixed(1)} МБ: ${await tail(s)}');
    }
    for (final s in m.videoOnly.where((s) => s.container == StreamContainer.mp4)) {
      // ignore: avoid_print
      print(
          'video ${s.tag} ${s.videoResolution} ${s.codec.mimeType} ${(s.size.totalMegaBytes).toStringAsFixed(1)} МБ: ${await tail(s)}');
    }
    // ignore: avoid_print
    print(
        'hls: ${await yt.videos.streamsClient.getHttpLiveStreamUrl(VideoId('kXYiU_JCYtU')).catchError((e) => 'нет: $e')}');
    yt.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
