// ignore_for_file: avoid_print
import 'package:echoes_mobile/services/spotify.dart';
Future<void> main() async {
  for (final n in ['LINKIN PARK', 'zxcursed', 'Miyagi & Andy Panda', 'Кишлак', 'TORONTOKYO', 'lil flash\$', 'The Neighbourhood']) {
    final sw = Stopwatch()..start();
    final a = await SpotifyService.instance.forArtist(n);
    print('$n → ${a == null ? 'не найден' : '${a.name}: ${a.monthlyListeners} слушателей/мес, фото ${a.image != null ? 'есть' : 'нет'} (${a.id})'} · ${sw.elapsedMilliseconds} мс');
  }
}
