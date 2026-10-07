// ignore_for_file: avoid_print
import 'dart:io';

import 'package:echoes_mobile/services/importer.dart';
import 'package:echoes_mobile/services/search.dart';

/// dart run tool/check_import_search.dart <файл .echoesplaylist>
Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    final sw = Stopwatch()..start();
    var lists = Importer.parse(File(args.first).readAsStringSync());
    lists = await Importer.resolve(lists);
    for (final (name, ts) in lists) {
      print('$name: ${ts.length} — yt ${ts.where((t) => t.isYt).length}, sc ${ts.where((t) => t.isSc).length}, '
          'отрывки ${ts.where((t) => t.isPreview).length}, по названию ${ts.where((t) => t.isQuery).length}');
    }
    print('импорт: ${sw.elapsedMilliseconds} мс');
  }
  for (final q in ['kosandra', 'after dark', 'sweater weather', 'кишлак']) {
    final r = await SearchService.search(q, SearchSource.all);
    print('\n«$q» (${r.length}):');
    for (final t in r.take(8)) {
      print('  ${t.isSc ? 'SC ' : 'YT '} ${t.artist} — ${t.title} (${t.seconds}s)');
    }
  }
}
