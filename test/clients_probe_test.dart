// Какие клиенты YouTube сейчас отдают звук ЦЕЛИКОМ (не только начало): качаем весь файл кусками по 1 МБ.
// flutter test test/clients_probe_test.dart --run-skipped   (видео — переменная окружения V)
@Tags(['network'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('клиенты YouTube', () async {
    final id = Platform.environment['V'] ?? 'LPCYK5VO-4k';
    final yt = YoutubeExplode();
    final clients = <String, List<YoutubeApiClient>?>{
      'android': [YoutubeApiClient.android],
      'default': null,
      'androidSdkless': [YoutubeApiClient.androidSdkless],
      'androidMusic': [YoutubeApiClient.androidMusic],
      'androidVr': [YoutubeApiClient.androidVr],
      'safari': [YoutubeApiClient.safari],
      'ios': [YoutubeApiClient.ios],
      'mweb': [YoutubeApiClient.mweb],
      'mediaConnect': [YoutubeApiClient.mediaConnect],
      'tv': [YoutubeApiClient.tv],
    };
    for (final e in clients.entries) {
      final sw = Stopwatch()..start();
      try {
        final m = e.value == null
            ? await yt.videos.streamsClient.getManifest(id)
            : await yt.videos.streamsClient.getManifest(id, ytClients: e.value);
        final a = m.audioOnly.where((s) => s.container == StreamContainer.mp4).toList()
          ..sort((x, y) => x.bitrate.compareTo(y.bitrate));
        if (a.isEmpty) {
          // ignore: avoid_print
          print('${e.key}: нет AAC');
          continue;
        }
        final s = a.last;
        final size = s.size.totalBytes;
        var got = 0, status = 0;
        final c = http.Client();
        for (var o = 0; o < size; o += 1 << 20) {
          final end = (o + (1 << 20) - 1).clamp(0, size - 1);
          final r = await c.get(s.url, headers: {'Range': 'bytes=$o-$end'});
          status = r.statusCode;
          if (status != 206 && status != 200) break;
          got += r.bodyBytes.length;
        }
        c.close();
        final ip = s.url.queryParameters['ip'];
        // ignore: avoid_print
        print('${e.key}: ${got == size ? 'ЦЕЛИКОМ' : 'ОБРЫВ на $got из $size (HTTP $status)'} '
            '${sw.elapsedMilliseconds} мс, ip=$ip, c=${s.url.queryParameters['c']}');
      } catch (err) {
        // ignore: avoid_print
        print('${e.key}: ОШИБКА ${'$err'.split('\n').first}');
      }
    }
    yt.close();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
