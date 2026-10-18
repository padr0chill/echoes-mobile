// ignore_for_file: experimental_member_use
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import 'yt.dart';

/// HTTP-клиент прокси (в тестах подменяется на подставной сервер).
@visibleForTesting
http.Client streamClient = http.Client();

/// Звук через встроенный мини-прокси: приложение само берёт поток кусками (Range-запросами) и
/// отдаёт их плееру. Нужен, когда плеер iOS не может открыть ссылку YouTube напрямую.
/// Это стриминг: данные идут в память (скачивание для офлайна — отдельно, services/offline.dart).
class YtProxySource extends StreamAudioSource {
  final StreamPick pick;

  YtProxySource(this.pick) : super(tag: 'yt-proxy');

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final total = pick.size;
    final s = start ?? 0;
    final e = (end ?? total).clamp(s, total);
    // кусок — заголовком Range (проверено: 206); запасной путь — параметр &range= в ссылке
    // тайм-ауты: тихо зависшее соединение не должно держать плеер в «буферизации» бесконечно
    var resp = await streamClient
        .send(http.Request('GET', pick.url)..headers['Range'] = 'bytes=$s-${e - 1}')
        .timeout(const Duration(seconds: 15));
    // 200 на запрос с середины — сервер отдал файл с начала, а плееру мы скажем «с байта s»: звук
    // после перемотки был бы не с того места. Такой ответ — тоже в запасной путь
    if ((resp.statusCode != 200 && resp.statusCode != 206) || (resp.statusCode == 200 && s > 0)) {
      if (resp.statusCode == 200) {
        await resp.stream.listen(null).cancel(); // весь файл не дочитывать — оборвать соединение
      } else {
        await resp.stream.drain<void>();
      }
      final byParam = pick.url.replace(queryParameters: {...pick.url.queryParameters, 'range': '$s-${e - 1}'});
      resp = await streamClient.send(http.Request('GET', byParam)).timeout(const Duration(seconds: 15));
    }
    if (resp.statusCode != 206 && resp.statusCode != 200) {
      await resp.stream.drain<void>();
      throw Exception('HTTP ${resp.statusCode}');
    }
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: e - s,
      offset: s,
      // нет данных 20 с — ошибка потока → плеер восстановит трек со свежей ссылкой
      stream: resp.stream.timeout(const Duration(seconds: 20)),
      contentType: pick.mime.contains('/') ? pick.mime.split(';').first : 'audio/mp4',
    );
  }
}
