@Tags(['network'])
library;

import 'dart:io';

import 'package:echoes_mobile/services/reference.dart';
import 'package:echoes_mobile/services/search.dart';
import 'package:echoes_mobile/services/ytm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('эталоны', () async {
    final q = Platform.environment['Q'] ?? 'Linkin Park Numb';
    final refs = await Reference.instance.lookup(q);
    for (final r in refs) {
      // ignore: avoid_print
      print('ref: ${r.artist} | ${r.title} | ${r.seconds}');
    }
    final ytm = await YtmService.instance.searchSongs(q);
    for (final t in ytm.take(8)) {
      // ignore: avoid_print
      print('ytm: ${t.artist} | ${t.title} | ${t.seconds} canon=${Reference.canonical(t, refs)} altered=${Reference.altered(t, refs)}');
    }
    final all = await SearchService.search(q, SearchSource.all);
    // ignore: avoid_print
    print('all: ${all.take(5).map((t) => '${t.title} ${t.seconds}').join(' | ')}');
  });
}
