@Tags(['network'])
library;

import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/wave.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('волна от трека — только YouTube Music', () async {
    final r = await Wave.instance.relatedFor(const Track(id: 'LPCYK5VO-4k', title: 'где', artist: 'zxcursed'));
    for (final t in r.take(8)) {
      // ignore: avoid_print
      print('W ${t.id} ${t.artist} — ${t.title} ${t.seconds}s ${t.art != null}');
    }
    expect(r.length, greaterThan(10));
    expect(r.where((t) => t.isSc), isEmpty);
  });
}
