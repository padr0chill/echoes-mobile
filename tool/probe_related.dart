// ignore_for_file: avoid_print
// Источники «похожих треков»: YouTube related и SoundCloud related.
import 'dart:convert';

import 'package:echoes_mobile/services/sc.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  final yt = YoutubeExplode();
  final sw = Stopwatch()..start();
  try {
    final v = await yt.videos.get('x1ZtIVuHph0');
    final rel = await yt.videos.getRelatedVideos(v);
    print('YT related: ${rel?.length ?? 0} in ${sw.elapsedMilliseconds} ms');
    for (final r in (rel ?? []).take(5)) {
      print('   ${r.author} — ${r.title} (${r.duration})');
    }
  } catch (e) {
    print('YT related FAIL: $e');
  }
  sw.reset();
  try {
    final res = await ScService.instance.search('Miyagi Kosandra');
    final id = res.first.id;
    final cid = await ScService.instance.clientId();
    final r =
        await http.get(Uri.https('api-v2.soundcloud.com', '/tracks/$id/related', {'client_id': cid, 'limit': '20'}));
    final col = (jsonDecode(r.body)['collection'] as List);
    print('SC related: HTTP ${r.statusCode}, ${col.length} in ${sw.elapsedMilliseconds} ms');
    for (final t in col.take(5)) {
      print('   ${t['user']['username']} — ${t['title']} (${t['policy']})');
    }
  } catch (e) {
    print('SC related FAIL: $e');
  }
  yt.close();
}
