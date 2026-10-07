@Tags(['network'])
library;

import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/lyrics.dart';
import 'package:flutter_test/flutter_test.dart';

// Качество «умного» поиска на настоящих треках (печатается только найденное название и оценка, не текст):
// flutter test test/lyrics_net_test.dart --run-skipped
void main() {
  const tracks = [
    Track(id: 'HbkC9qHA6wU', title: 'Kosandra', artist: 'Miyagi & Andy Panda', seconds: 222),
    Track(id: 'x1', title: 'Numb (Official Music Video) [4K UPGRADE]', artist: 'Linkin Park', seconds: 186),
    Track(id: 'x2', title: 'Грязь', artist: 'Кишлак - Topic', seconds: 142),
    Track(id: 'x3', title: 'Sweater Weather', artist: 'The Neighbourhood', seconds: 240),
    Track(id: 'x4', title: 'lil flash\$ - project x (dilemma)', artist: 'mayyski', seconds: 120),
    Track(id: 'x5', title: 'Ливаю', artist: 'n01r', seconds: 85),
  ];
  for (final t in tracks) {
    test(t.title, () async {
      final list = await LyricsService.instance.search(t, quick: true);
      final best = list.isEmpty ? null : list.first;
      final ly = best?.toLyrics();
      // ignore: avoid_print
      print('${t.artist} — ${t.title}\n   → ${best == null ? 'не найдено' : '${best.artist} — ${best.title} '
          '(${best.seconds} с, оценка ${best.score.toStringAsFixed(1)}, ${best.hasSynced ? 'синхронный' : 'обычный'}, '
          '${ly?.lines.length ?? 0} строк, ${best.score >= 4.2 ? 'покажется сам' : 'только в «Найти вручную»'})'}');
    }, timeout: const Timeout(Duration(seconds: 60)));
  }
}
