// Живая проверка поиска: в первых результатах не должно быть ускоренных/замедленных версий.
// flutter test test/search_quality_test.dart --run-skipped
@Tags(['network'])
library;

import 'package:echoes_mobile/services/search.dart';
import 'package:echoes_mobile/services/text_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final q in [
    'zxcursed где',
    'Linkin Park Numb',
    'Miyagi Kosandra',
    'Kai Angel Leopard Red',
    'кишлак мне похуй'
  ]) {
    test(q, () async {
      final r = await SearchService.search(q, SearchSource.all);
      for (final t in r.take(6)) {
        // ignore: avoid_print
        print(
            '$q → ${t.artist} — ${t.title} (${t.seconds}s) ${t.isSc ? 'SC' : 'YT'} ${Versions.of('${t.artist} ${t.title}')}');
      }
      final top = r.take(3).where((t) => Versions.extra('${t.artist} ${t.title}', q).isNotEmpty);
      expect(top, isEmpty, reason: 'в первых трёх — другие версии');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
