// ignore_for_file: avoid_print
import 'package:echoes_mobile/services/sc.dart';

/// Проверка: все треки исполнителя (с пагинацией), альбомы, треки альбома, поиск альбомов.
Future<void> main() async {
  final sc = ScService.instance;
  for (final id in [1818488, 1227431371]) {
    final sw = Stopwatch()..start();
    final tracks = await sc.artistTracks(id);
    print('  full ${tracks.where((t) => t.isSc).length}, previews ${tracks.where((t) => t.isPreview).length}');
    final albums = await sc.artistAlbums(id);
    print('user $id: tracks ${tracks.length}, albums ${albums.length} (${sw.elapsedMilliseconds} ms)');
    for (final a in albums.take(4)) {
      print('  ${a.kindLabel} ${a.year} «${a.title}» ${a.count} тр.');
    }
    if (albums.isNotEmpty) {
      final t = await sc.albumTracks(albums.first.id);
      print('  first album tracks: ${t.length}/${albums.first.count}: ${t.take(4).map((x) => x.title).join(' | ')}');
    }
  }
  for (final q in ['hybrid theory', 'зxcursed', 'miyagi']) {
    final r = await sc.searchAlbums(q);
    print('search "$q": ${r.take(4).map((a) => '${a.title} — ${a.artist} (${a.count})').join('; ')}');
  }
}
