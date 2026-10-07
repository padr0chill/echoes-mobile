// Мини-прокси на настоящем потоке YouTube (нужен интернет): flutter test test/proxy_test.dart --run-skipped
// ignore_for_file: avoid_print
@Tags(['network'])
library;

import 'package:echoes_mobile/services/stream_source.dart';
import 'package:echoes_mobile/services/yt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('proxy serves ranges of a real stream', () async {
    final pick = await YtService.instance.stream('x1ZtIVuHph0');
    expect(pick.size, greaterThan(100000));
    final probe = await http.get(pick.url, headers: {'Range': 'bytes=0-65535'});
    print('pick c=${pick.url.queryParameters['c']} itag=${pick.url.queryParameters['itag']} client#${pick.client} '
        'size=${pick.size} mime=${pick.mime} plain-range=${probe.statusCode}');
    final src = YtProxySource(pick);

    Future<int> read(int? s, int? e) async {
      final r = await src.request(s, e);
      var n = 0;
      await for (final chunk in r.stream) {
        n += chunk.length;
      }
      expect(r.sourceLength, pick.size);
      expect(r.contentType, anyOf(startsWith('audio/'), startsWith('video/')));
      return n;
    }

    expect(await read(0, 65536), 65536); // начало
    final mid = pick.size ~/ 2;
    expect(await read(mid, mid + 32768), 32768); // перемотка в середину
    expect(await read(pick.size - 1000, null), 1000); // до конца
    print('stream ${pick.mime} ${pick.size} bytes via client #${pick.client} — proxy OK');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
