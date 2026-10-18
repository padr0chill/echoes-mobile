// «Умный» поиск текста и синхронизация — без сети.
import 'package:echoes_mobile/services/lyrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('чистка названия: feat, prod, клип, «исполнитель - название» в названии', () {
    expect(LyricsService.cleanup('Miyagi & Andy Panda', 'Kosandra (Official Video)'), ('Miyagi', 'Kosandra'));
    expect(LyricsService.cleanup('lil flash\$', 'lil flash\$ - project x (prod. dzhioev)'), (
      'lil flash\$',
      'project x',
    ));
    expect(LyricsService.cleanup('Кишлак - Topic', 'Грязь [Премьера клипа]'), ('Кишлак', 'Грязь'));
    expect(LyricsService.cleanup('LINKIN PARK', 'Numb feat. Someone'), ('LINKIN PARK', 'Numb'));
  });

  test('сравнение с транслитерацией и слитным написанием', () {
    expect(LyricsService.similarity('Мияги', 'Miyagi'), 1.0);
    expect(LyricsService.similarity('The Neighbourhood', 'theneighbourhood'), 1.0);
    expect(LyricsService.similarity('Numb', 'Numb (Live)'), 1.0);
    expect(LyricsService.similarity('Numb', 'In the End'), 0.0);
  });

  test('авто-синхронизация: по порядку, внутри длительности, длинные строки — дольше', () {
    final ly = LyricsService.autoSync([
      '',
      'короткая',
      'очень длинная строка с множеством разных слогов внутри',
      '',
      'ещё строка',
      'финал',
    ], const Duration(minutes: 3));
    expect(ly.synced, isTrue);
    expect(ly.approx, isTrue);
    expect(ly.lines.first.text, 'короткая'); // пустые строки в начале убраны
    for (var i = 1; i < ly.lines.length; i++) {
      expect(ly.lines[i].at > ly.lines[i - 1].at, isTrue);
    }
    expect(ly.lines.first.at >= const Duration(seconds: 2), isTrue);
    expect(ly.lines.last.at < const Duration(minutes: 3), isTrue);
    final short = ly.lines[1].at - ly.lines[0].at, long = ly.lines[2].at - ly.lines[1].at;
    expect(long > short, isTrue);
  });

  test('LRC: сохранение и чтение, сдвиг не уходит в минус', () {
    final ly = Lyrics(
      const [LyricLine(Duration(milliseconds: 1500), 'a'), LyricLine(Duration(seconds: 65), 'b')],
      true,
      source: 'синхронизировано вручную',
    );
    final back = LyricsService.parseLrc(ly.toLrc());
    expect(back.map((l) => l.at.inMilliseconds).toList(), [1500, 65000]);
    expect(back.map((l) => l.text).toList(), ['a', 'b']);
    final early = ly.shifted(const Duration(seconds: -2));
    expect(early.lines.first.at, Duration.zero);
    expect(early.lines.last.at, const Duration(seconds: 63));
    // T24в: «раньше», потом «позже» — вступление возвращается на место, а не залипает на 0:00
    final back2 = early.shifted(const Duration(seconds: 2));
    expect(back2.lines.first.at, const Duration(milliseconds: 1500));
    // сдвиг переживает сохранение
    final saved = LyricsService.parseLrc(early.toLrc());
    expect(saved.first.at, const Duration(milliseconds: 1500)); // тайминги как были
    expect(early.toLrc(), contains('[shift:-2000]'));
  });

  test('T24г: тайминги подгоняются только при разнице в скорости > 3 %', () {
    final ly = Lyrics(const [LyricLine(Duration(seconds: 100), 'a')], true, srcSeconds: 200);
    expect(ly.fitTo(204).lines.first.at, const Duration(seconds: 100)); // 2 % — длиннее концовка, не скорость
    expect(ly.fitTo(220).lines.first.at, const Duration(seconds: 110)); // 10 % — ускоренная/замедленная
  });
}
