import 'package:echoes_mobile/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => appLangSetting = 'ru');

  test('русский — как в коде, английский — из словаря, с подстановкой', () {
    appLangSetting = 'ru';
    expect(tr('Скачано: {0} тр. · {1}', [3, '5 МБ']), 'Скачано: 3 тр. · 5 МБ');
    appLangSetting = 'en';
    expect(tr('Скачано: {0} тр. · {1}', [3, '5 MB']), 'Downloaded: 3 tracks · 5 MB');
    expect(tr('{0} тр.', [1]), '1 track');
    expect(tr('{0} тр.', [11]), '11 tracks');
    expect(tr('Мне нравится'), 'Liked');
    expect(tr('Плоский'), 'Flat');
    expect(tr('Какой-то текст без перевода'), 'Какой-то текст без перевода');
  });
}
