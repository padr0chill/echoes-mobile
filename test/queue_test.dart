// Очередь как в Spotify: «В очередь» — сразу после текущего (после уже добавленных), даже если трек
// уже есть в длинном плейлисте и даже «вперемешку».
import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/audio.dart';
import 'package:echoes_mobile/services/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track tr(String id) => Track(id: id, title: id, artist: 'a', seconds: 100);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Store.instance.load();
    audio = EchoesAudio();
  });

  setUp(() {
    audio.tracks.value = [for (var i = 0; i < 10; i++) tr('t$i')];
    audio.index.value = 2;
    audio.upNext.value = 0;
    audio.shuffle.value = false;
  });

  List<String> ids() => audio.tracks.value.map((t) => t.id).toList();

  test('новый трек — сразу после текущего, по порядку добавления', () {
    audio.addToQueue(tr('x'));
    audio.addToQueue(tr('y'));
    expect(ids().sublist(2, 6), ['t2', 'x', 'y', 't3']);
    expect(audio.upNext.value, 2);
  });

  test('трек, который уже есть дальше в плейлисте, переезжает вперёд (а не игнорируется)', () {
    audio.addToQueue(tr('t8'));
    expect(ids().sublist(2, 5), ['t2', 't8', 't3']);
    expect(ids().where((i) => i == 't8').length, 1);
  });

  test('трек из уже сыгранных тоже переезжает, текущий не сбивается', () {
    audio.addToQueue(tr('t0'));
    expect(audio.current!.id, 't2');
    expect(ids()[audio.index.value + 1], 't0');
  });

  test('«Играть следующим» — впереди добавленных', () {
    audio.addToQueue(tr('x'));
    audio.playNext(tr('y'));
    expect(ids().sublist(2, 5), ['t2', 'y', 'x']);
    expect(audio.upNext.value, 2);
  });

  test('вперемешку: добавленные всё равно играют следующими', () async {
    audio.shuffle.value = true;
    audio.addToQueue(tr('x'));
    audio.addToQueue(tr('y'));
    await audio.skipToNext();
    expect(audio.current!.id, 'x');
    expect(audio.upNext.value, 1);
    await audio.skipToNext();
    expect(audio.current!.id, 'y');
    expect(audio.upNext.value, 0);
  });

  test('удаление из «Далее в очереди» уменьшает счётчик', () {
    audio.addToQueue(tr('x'));
    audio.addToQueue(tr('y'));
    audio.removeAt(3);
    expect(audio.upNext.value, 1);
    expect(ids().sublist(2, 4), ['t2', 'y']);
  });

  test('вперемешку: очередь реально перемешана — играет ровно то, что показано', () async {
    audio.toggleShuffle();
    expect(audio.shuffle.value, isTrue);
    expect(audio.current!.id, 't2'); // текущий не сбился
    expect(ids().toSet(), {for (var i = 0; i < 10; i++) 't$i'}); // все треки на месте
    final shown = ids().sublist(audio.index.value + 1, audio.index.value + 4);
    for (final want in shown) {
      await audio.skipToNext();
      expect(audio.current!.id, want);
    }
    audio.toggleShuffle(); // выключить — для следующих тестов
  });

  test('вперемешку не трогает «Далее в очереди»', () {
    audio.addToQueue(tr('x'));
    audio.addToQueue(tr('y'));
    audio.toggleShuffle();
    expect(ids().sublist(audio.index.value, audio.index.value + 3), ['t2', 'x', 'y']);
    audio.toggleShuffle();
  });

  test('выключили вперемешку — прежний порядок, с того же трека', () async {
    final before = ids();
    audio.toggleShuffle();
    await audio.skipToNext();
    final now = audio.current!.id;
    audio.toggleShuffle();
    expect(ids(), before);
    expect(audio.current!.id, now);
  });
}
