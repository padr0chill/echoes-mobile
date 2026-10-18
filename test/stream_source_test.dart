import 'package:echoes_mobile/services/stream_source.dart';
import 'package:echoes_mobile/services/yt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// T25: сервер, который не выполнил Range (отдал файл с начала), не должен сдвигать звук после перемотки.
void main() {
  final body = List<int>.generate(1000, (i) => i % 256);
  final pick = StreamPick(Uri.parse('https://example.com/a.m4a?x=1'), body.length, 'audio/mp4', 0);

  Future<List<int>> read(int start, int end) async {
    final r = await YtProxySource(pick).request(start, end);
    expect(r.offset, start);
    return [for (final c in await r.stream.toList()) ...c];
  }

  test('Range игнорируется (200 с начала) → запасной путь &range= с нужными байтами', () async {
    final seen = <Uri>[];
    streamClient = MockClient((req) async {
      seen.add(req.url);
      final r = req.url.queryParameters['range'];
      if (r != null) {
        final p = r.split('-').map(int.parse).toList();
        return http.Response.bytes(body.sublist(p[0], p[1] + 1), 200);
      }
      return http.Response.bytes(body, 200); // заголовок Range проигнорирован
    });
    final got = await read(500, 600);
    expect(got, body.sublist(500, 600));
    expect(seen.length, 2);
    expect(seen.last.queryParameters['range'], '500-599');
  });

  test('с начала файла 200 — нормальный ответ, без лишнего запроса', () async {
    var calls = 0;
    streamClient = MockClient((req) async {
      calls++;
      return http.Response.bytes(body.sublist(0, 100), 200);
    });
    expect(await read(0, 100), body.sublist(0, 100));
    expect(calls, 1);
  });

  test('206 — как есть', () async {
    streamClient = MockClient((req) async {
      expect(req.headers['Range'], 'bytes=10-19');
      return http.Response.bytes(body.sublist(10, 20), 206);
    });
    expect(await read(10, 20), body.sublist(10, 20));
  });
}
