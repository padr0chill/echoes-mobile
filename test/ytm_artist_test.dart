// Живая проверка страницы исполнителя YouTube Music: дискография целиком, треки альбома, все песни.
@Tags(['network'])
library;

import 'dart:io';

import 'package:echoes_mobile/services/ytm_artist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('исполнитель YouTube Music', () async {
    final name = Platform.environment['A'] ?? 'zxcursed';
    final b = YtmBrowse.instance;
    final id = await b.findArtist(name);
    expect(id, isNotNull);
    final p = await b.artist(id!);
    // ignore: avoid_print
    print('${p.name} | ${p.monthly} | подписчиков ${p.subscribers} | фото ${p.image != null}');
    for (final t in p.top) {
      // ignore: avoid_print
      print('  топ: ${t.title} — ${t.artist} (${t.seconds}s) ${p.plays[t.id]}');
    }
    // ignore: avoid_print
    print(
        'альбомы ${p.albums.length} (+ещё ${p.albumsMore != null}), синглы ${p.singles.length} (+ещё ${p.singlesMore != null}), похожие ${p.similar.length}');
    if (p.singlesMore != null) {
      final all = await b.discography(p.singlesMore!, p.name);
      // ignore: avoid_print
      print('все синглы: ${all.length}: ${all.take(4).map((a) => '${a.title} ${a.year} ${a.kind}').join(', ')}');
      expect(all.length, greaterThan(p.singles.length - 1));
    }
    if (p.albums.isNotEmpty) {
      final tr = await b.albumTracks(p.albums.first.ytm!);
      // ignore: avoid_print
      print(
          'альбом «${p.albums.first.title}»: ${tr.length} треков, обложка ${tr.first.art != null}, ${tr.first.title} ${tr.first.seconds}s');
    }
    if (p.songsPlaylist != null) {
      final all = await b.playlist(p.songsPlaylist!, artist: p.name);
      // ignore: avoid_print
      print('все песни: ${all.length}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
