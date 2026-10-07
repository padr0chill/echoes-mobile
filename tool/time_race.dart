// ignore_for_file: avoid_print
import 'dart:async';

import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/sc.dart';
import 'package:echoes_mobile/services/yt.dart';

/// Через сколько трек готов к игре при «гонке» YouTube ∥ SoundCloud (как в audio.dart):
/// обычный случай и случай «YouTube отказывает телефону». dart run tool/time_race.dart
Future<void> main() async {
  await ScService.instance.clientId(); // на телефоне ключ уже сохранён с прошлого запуска
  const tracks = [
    Track(id: 'HbkC9qHA6wU', title: 'Kosandra', artist: 'Miyagi & Andy Panda', seconds: 222),
    Track(id: 'eHECKcnloCE', title: 'Papercut', artist: 'Linkin Park', seconds: 185),
    Track(id: 'fJ9rUzIMcZQ', title: 'Bohemian Rhapsody', artist: 'Queen', seconds: 355),
  ];
  for (final ytWorks in [true, false]) {
    print(ytWorks ? '\n— YouTube работает —' : '\n— YouTube отказывает (как на телефоне) —');
    for (final t in tracks) {
      final sw = Stopwatch()..start();
      Future<StreamPick> one(int i) => ytWorks
          ? YtService.instance.streamWith(t.id, i).timeout(const Duration(seconds: 7))
          : Future.delayed(const Duration(milliseconds: 1500), () => throw Exception('unplayable'));
      final yt = Future.any([one(0), one(1)]).then<int?>((_) => sw.elapsedMilliseconds, onError: (_) => null);
      final sc = () async {
        final m = await ScService.instance.match(t.artist, t.title, t.seconds);
        if (m == null) return null;
        await ScService.instance.streamUrl(m);
        return sw.elapsedMilliseconds;
      }();
      final ys = await yt, ss = await sc;
      // правило из audio.dart: YouTube — сразу, SoundCloud — с форой 0,8 с (YouTube уже отказывал — без форы)
      final ready = [if (ys != null) ys, if (ss != null) ss + (ytWorks ? 800 : 0)];
      ready.sort();
      print('  ${t.artist} — ${t.title}: YouTube ${ys ?? '—'} мс, SoundCloud ${ss ?? 'нет'} мс → '
          'готов через ${ready.isEmpty ? 'не нашлось' : '${ready.first} мс'}');
    }
  }
}
