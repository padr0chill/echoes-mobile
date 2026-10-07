// ignore_for_file: experimental_member_use
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import 'yt.dart';

final _client = http.Client();

/// Звук через встроенный мини-прокси: приложение само берёт поток кусками (Range-запросами) и
/// отдаёт их плееру. Нужен, когда плеер iOS не может открыть ссылку YouTube напрямую.
/// Это по-прежнему стриминг: данные идут в память и не сохраняются в файлы.
class YtProxySource extends StreamAudioSource {
  final StreamPick pick;

  YtProxySource(this.pick) : super(tag: 'yt-proxy');

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final total = pick.size;
    final s = start ?? 0;
    final e = (end ?? total).clamp(s, total);
    // кусок — заголовком Range (проверено: 206); запасной путь — параметр &range= в ссылке
    var resp = await _client.send(http.Request('GET', pick.url)..headers['Range'] = 'bytes=$s-${e - 1}');
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      await resp.stream.drain<void>();
      final byParam = pick.url.replace(queryParameters: {...pick.url.queryParameters, 'range': '$s-${e - 1}'});
      resp = await _client.send(http.Request('GET', byParam));
    }
    if (resp.statusCode != 206 && resp.statusCode != 200) {
      await resp.stream.drain<void>();
      throw Exception('HTTP ${resp.statusCode}');
    }
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: e - s,
      offset: s,
      stream: resp.stream,
      contentType: pick.mime.contains('/') ? pick.mime.split(';').first : 'audio/mp4',
    );
  }
}
