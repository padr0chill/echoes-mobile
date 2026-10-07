@Tags(['network'])
library;

import 'dart:io';

import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/offline.dart';
import 'package:echoes_mobile/services/sc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Загрузка в приложение — по-настоящему, с сетью: flutter test test/offline_test.dart --run-skipped
void main() {
  final dir = Directory.systemTemp.createTempSync('echoes_offline');

  Future<void> check(Track t) async {
    final f = File('${dir.path}/${t.id.replaceAll(':', '_')}.part');
    final sw = Stopwatch()..start();
    final ext = await Offline.instance.downloadTo(t, f);
    final head = f.openSync().readSync(12);
    // ignore: avoid_print
    print('${t.artist} — ${t.title}: ${(f.lengthSync() / 1048576).toStringAsFixed(1)} МБ .$ext '
        '${sw.elapsedMilliseconds} мс, начало: ${String.fromCharCodes(head.where((b) => b >= 32 && b < 127))}');
    expect(f.lengthSync(), greaterThan(500000));
  }

  test('SoundCloud', () async {
    final r = await ScService.instance.searchTracks('zxcursed blessed');
    await check(r.first);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('YouTube', () async {
    await check(const Track(id: 'HbkC9qHA6wU', title: 'Kosandra', artist: 'Miyagi & Andy Panda', seconds: 222));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('отрывок SoundCloud → YouTube', () async {
    final al = await ScService.instance.searchAlbums('hybrid theory');
    final ts = await ScService.instance.albumTracks(al.first.id);
    await check(ts.firstWhere((t) => t.isPreview));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
