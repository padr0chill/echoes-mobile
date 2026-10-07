// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:http/http.dart' as http;

/// YouTube Music: поиск только песен (официальные записи) через внутренний API music.youtube.com.
Future<void> main(List<String> args) async {
  final q = args.isEmpty ? 'miyagi kosandra' : args.join(' ');
  final r = await http.post(
    Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false'),
    headers: {
      'Content-Type': 'application/json',
      'Origin': 'https://music.youtube.com',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36',
    },
    body: jsonEncode({
      'context': {
        'client': {'clientName': 'WEB_REMIX', 'clientVersion': '1.20241111.01.00', 'hl': 'ru', 'gl': 'RU'},
      },
      'query': q,
      'params': 'EgWKAQIIAWoKEAkQBRAKEAMQBA==',
    }),
  );
  print('HTTP ${r.statusCode}, ${r.body.length} bytes');
  final j = jsonDecode(r.body);
  var n = 0;
  void walk(dynamic x) {
    if (x is Map) {
      final it = x['musicResponsiveListItemRenderer'];
      if (it is Map && n < 10) {
        n++;
        final cols = (it['flexColumns'] as List)
            .map((c) => ((c['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] as List?) ?? [])
                .map((r) => r['text'])
                .join())
            .toList();
        final vid = it['playlistItemData']?['videoId'];
        final thumbs = it['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
        print('$vid | ${cols.join(' || ')} | ${thumbs?.last['url']}');
        return;
      }
      x.values.forEach(walk);
    } else if (x is List) {
      x.forEach(walk);
    }
  }

  walk(j);
}
