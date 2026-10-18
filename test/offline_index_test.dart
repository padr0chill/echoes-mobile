import 'dart:convert';
import 'dart:io';

import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/offline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Папки приложения — во временной папке теста.
class _Paths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final String root;
  _Paths(this.root);
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

Map<String, dynamic> _entry(String file, String id, {int bytes = 3}) => {
  'f': file,
  'b': bytes,
  't': Track(id: id, title: 't $id', artist: 'a').toJson(),
};

void main() {
  late Directory root;
  late Directory off;
  final o = Offline.instance;

  setUp(() {
    root = Directory.systemTemp.createTempSync('echoes_off_');
    off = Directory('${root.path}/offline')..createSync();
    PathProviderPlatform.instance = _Paths(root.path);
    o.resetForTest();
  });

  tearDown(() => root.deleteSync(recursive: true));

  void file(String name) => File('${off.path}/$name').writeAsStringSync('abc');
  void index(Object j) => File('${off.path}/index.json').writeAsStringSync(jsonEncode(j));

  group('T03: имена файлов', () {
    test('кириллица не склеивается в одно имя', () {
      expect(Offline.safeName('q:Кино — Пачка'), isNot(Offline.safeName('q:Сплин — Мать')));
    });
    test('id YouTube не меняется', () {
      expect(Offline.safeName('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });
    test('в имени нет символов пути', () {
      expect(Offline.safeName('yt:../../../ab'), isNot(contains('/')));
      expect(Offline.safeName('yt:../../../ab'), isNot(contains('..')));
    });
    test('записи, которые раньше совпали по файлу, убираются при загрузке', () async {
      file('q_____________.m4a');
      file('good.m4a');
      index({
        'q:Кино — Пачка': _entry('q_____________.m4a', 'q:Кино — Пачка'),
        'q:Сплин — Мать': _entry('q_____________.m4a', 'q:Сплин — Мать'),
        'good': _entry('good.m4a', 'good'),
      });
      await o.load();
      expect(o.tracks.map((t) => t.id), ['good']);
      expect(File('${off.path}/q_____________.m4a').existsSync(), isFalse);
    });
  });

  group('T06: индекс', () {
    test('одна битая запись не отменяет остальные', () async {
      file('a.m4a');
      file('b.m4a');
      index({
        'a': _entry('a.m4a', 'a'),
        'bad': {'f': 5, 'b': 'x'},
        'b': _entry('b.m4a', 'b'),
      });
      await o.load();
      expect(o.tracks.map((t) => t.id).toSet(), {'a', 'b'});
    });

    test('испорченный целиком индекс сохраняется как .broken, загрузка не падает', () async {
      File('${off.path}/index.json').writeAsStringSync('{"a": {"f": "a.m4a", "b"');
      await o.load();
      expect(o.count, 0);
      expect(File('${off.path}/index.json.broken').existsSync(), isTrue);
    });

    test('недокачанные .part удаляются на старте', () async {
      file('x.part');
      await o.load();
      expect(File('${off.path}/x.part').existsSync(), isFalse);
    });
  });

  test('T05: «Очистить» удаляет скачанное, свои файлы остаются', () async {
    file('d1.m4a');
    file('d2.m4a');
    file('local_1.mp3');
    file('orphan.m4a');
    index({'d1': _entry('d1.m4a', 'd1'), 'd2': _entry('d2.m4a', 'd2'), 'local:1': _entry('local_1.mp3', 'local:1')});
    await o.load();
    expect(o.downloadedCount, 2);
    expect(o.localCount, 1);
    await o.clear();
    expect(o.downloadedCount, 0);
    expect(o.localTracks.map((t) => t.id), ['local:1']);
    expect(File('${off.path}/local_1.mp3').existsSync(), isTrue);
    expect(File('${off.path}/d1.m4a').existsSync(), isFalse);
    expect(File('${off.path}/orphan.m4a').existsSync(), isFalse);
    // индекс записан заново и читается
    o.resetForTest();
    await o.load();
    expect(o.tracks.map((t) => t.id), ['local:1']);
  });
}
