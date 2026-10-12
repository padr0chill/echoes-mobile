import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/search.dart';
import 'package:echoes_mobile/services/text_match.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String artist, String title, [int s = 200]) =>
    Track(id: '$artist$title', title: title, artist: artist, seconds: s);

void main() {
  test('пометки версий — целыми словами, в любом написании', () {
    expect(Versions.of('Linkin Park — Numb (Live in Texas)'), {'live'});
    expect(Versions.of('Pharrell — Alive'), isEmpty); // «alive» — не концерт
    expect(Versions.of('zxcursed — где (sped-up)'), {'sped'});
    expect(Versions.of('zxcursed — где ускоренная версия'), {'sped'});
    expect(Versions.of('кишлак — мне похуй (𝒔𝒍𝒐𝒘𝒆𝒅 + 𝒓𝒆𝒗𝒆𝒓𝒃)'), {'slowed', 'reverb'});
    expect(Versions.of('Miyagi — Minor (концерт в Москве)'), {'live'});
    expect(Versions.of('Kai Angel — Leopard Red'), isEmpty);
    expect(Versions.of('Deep Purple — Pitch Black'), isEmpty);
    expect(Versions.of('X — Song (Nightcore)'), {'nightcore'});
    expect(Versions.of('Miyagi — Kosandra (slow)'), {'slowed'});
    expect(Versions.of('Slow Dancing in the Dark'), isEmpty);
  });

  test('поиск: ускоренные убраны, концертные ниже, но если искали — остаются', () {
    final list = [
      t('Linkin Park', 'Numb (Live)'),
      t('Linkin Park', 'Numb (sped up)'),
      t('Linkin Park', 'Numb'),
    ];
    expect(SearchService.clean('linkin park numb', list).map((x) => x.title), ['Numb', 'Numb (Live)']);
    expect(SearchService.clean('numb sped up', list).map((x) => x.title), ['Numb (sped up)', 'Numb', 'Numb (Live)']);
    expect(SearchService.clean('numb live', list).first.title, 'Numb (Live)');
  });

  test('склейка площадок: «Numb» и «Numb (Live)» — разные записи', () {
    expect(SearchService.same(t('Linkin Park', 'Numb', 185), t('Linkin Park', 'Numb (Live)', 188)), isFalse);
    expect(SearchService.same(t('Linkin Park', 'Numb', 185), t('Linkin Park', 'Numb', 186)), isTrue);
  });
}
