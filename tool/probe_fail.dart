// ignore_for_file: avoid_print
import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/sc.dart';
import 'package:echoes_mobile/services/yt.dart';
import 'package:echoes_mobile/services/ytm.dart';

Future<void> main() async {
  const t = Track(id: '?', title: '2000 asleep', artist: 'TORONTOKYO', seconds: 130);
  final sc = await ScService.instance.search('TORONTOKYO 2000 asleep', limit: 10);
  for (final s in sc.take(6)) {
    print('SC: ${s.artist} — ${s.title} ${s.seconds}s playable=${s.playable} snippet=${s.snippet}');
  }
  print('SC match strict: ${(await ScService.instance.match(t.artist, t.title, t.seconds))?.title}');
  print('SC match loose: ${(await ScService.instance.match(t.artist, t.title, t.seconds, strict: false))?.title}');
  final ytm = await YtmService.instance.searchSongs('TORONTOKYO 2000 asleep', limit: 5);
  for (final y in ytm) {
    print('YTM: ${y.id} ${y.artist} — ${y.title} ${y.seconds}s');
  }
  final yt = await YtService.instance.search('TORONTOKYO 2000 asleep');
  for (final y in yt.take(5)) {
    print('YT: ${y.id} ${y.artist} — ${y.title} ${y.seconds}s');
  }
  for (final id in [...ytm.take(2).map((e) => e.id), ...yt.take(2).map((e) => e.id)]) {
    for (var i = 0; i < YtService.clients.length; i++) {
      try {
        final p = await YtService.instance.streamWith(id, i);
        print('  $id client#$i OK ${p.mime} ${(p.size / 1e6).toStringAsFixed(1)}MB');
      } catch (e) {
        print('  $id client#$i FAIL ${'$e'.split('\n').first}');
      }
    }
  }
}
