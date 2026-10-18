import 'package:echoes_mobile/services/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T04: одно испорченное значение в настройках не должно ломать запуск и терять остальное.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> load(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    await Store.instance.load();
    return SharedPreferences.getInstance();
  }

  test('liked — не JSON: загрузка не падает, оригинал сохранён, остальное на месте', () async {
    final p = await load({'liked': 'not json', 'history': '[{"id":"h1","t":"x"}]', 'accent': 2});
    expect(Store.instance.liked, isEmpty);
    expect(p.getString('liked_broken'), 'not json');
    expect(Store.instance.history.map((t) => t.id), ['h1']);
    expect(Store.instance.accentIndex, 2);
  });

  test('битый трек пропускается, остальные загружаются', () async {
    final p = await load({'liked': '[{"id":"a","t":"x"},{"id":5}]'});
    expect(Store.instance.liked.map((t) => t.id), ['a']);
    expect(p.getString('liked_broken'), isNotNull);
  });

  test('статистика по исполнителям — не словарь: пусто, остальное загружено', () async {
    await load({'artist_s': '[1,2]', 'plays': 7});
    expect(Store.instance.artistSeconds, isEmpty);
    expect(Store.instance.plays, 7);
  });

  test('длительность 215.0 (дробное) читается', () async {
    await load({'liked': '[{"id":"a","t":"x","s":215.0}]'});
    expect(Store.instance.liked.single.seconds, 215);
  });

  test('значение не того типа (строка вместо числа) не роняет загрузку', () async {
    await load({'accent': 'two', 'xfade': 3});
    expect(Store.instance.accentIndex, 0);
    expect(Store.instance.crossfade, 3.0);
  });

  test('плейлист с битым треком сохраняет остальные треки', () async {
    await load({'playlists': '[{"n":"P","tr":[{"id":"a"},{"t":"без id"},{"id":"b"}]}]'});
    expect(Store.instance.playlists.single.tracks.map((t) => t.id), ['a', 'b']);
  });
}
