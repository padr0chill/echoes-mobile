// Как YouTube режет поток: одним запросом целиком? свежая ссылка на каждый кусок?
@Tags(['network'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('куски', () async {
    final id = Platform.environment['V'] ?? 'LPCYK5VO-4k';
    final yt = YoutubeExplode();
    Future<MuxedStreamInfo> pick() async {
      final m = await yt.videos.streamsClient.getManifest(id, ytClients: [YoutubeApiClient.android]);
      final a = m.muxed.where((s) => s.container == StreamContainer.mp4).toList()
        ..sort((x, y) => x.bitrate.compareTo(y.bitrate));
      // ignore: avoid_print
      print('muxed: ${a.map((x) => x.tag).toList()}');
      return a.first;
    }

    final c = http.Client();
    // A) весь файл одним запросом
    var s = await pick();
    final size = s.size.totalBytes;
    var r = await c.get(s.url, headers: {'Range': 'bytes=0-${size - 1}'});
    // ignore: avoid_print
    print('A одним запросом: HTTP ${r.statusCode}, ${r.bodyBytes.length}/$size');
    // A2) без Range
    s = await pick();
    r = await c.get(s.url);
    // ignore: avoid_print
    print('A2 без Range: HTTP ${r.statusCode}, ${r.bodyBytes.length}/$size');
    // B) свежая ссылка на каждый мегабайт
    var got = 0;
    for (var o = 0; o < size; o += 1 << 20) {
      final u = (await pick()).url;
      final end = (o + (1 << 20) - 1).clamp(0, size - 1);
      final rr = await c.get(u, headers: {'Range': 'bytes=$o-$end'});
      // ignore: avoid_print
      print('B кусок $o: HTTP ${rr.statusCode} ${rr.bodyBytes.length}');
      if (rr.statusCode != 206) break;
      got += rr.bodyBytes.length;
    }
    // ignore: avoid_print
    print('B итого $got/$size');
    // C) одна ссылка, куски по 512 КБ — где обрыв
    s = await pick();
    got = 0;
    for (var o = 0; o < size; o += 1 << 19) {
      final end = (o + (1 << 19) - 1).clamp(0, size - 1);
      final rr = await c.get(s.url, headers: {'Range': 'bytes=$o-$end'});
      if (rr.statusCode != 206) {
        // ignore: avoid_print
        print('C обрыв на $o (HTTP ${rr.statusCode})');
        break;
      }
      got += rr.bodyBytes.length;
    }
    // ignore: avoid_print
    print('C итого $got/$size');
    c.close();
    yt.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
