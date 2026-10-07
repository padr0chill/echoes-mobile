import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/audio.dart';
import 'package:echoes_mobile/services/lyrics.dart';
import 'package:echoes_mobile/services/store.dart';
import 'package:echoes_mobile/skins/milkdrop.dart';
import 'package:echoes_mobile/skins/milkdrop_engine.dart';
import 'package:echoes_mobile/skins/milkdrop_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// MilkDrop как на ПК: обратная связь + волны + ремап. Скриншоты разных пресетов:
// flutter test test/milkdrop_test.dart --run-skipped --update-goldens
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.load();
    audio = EchoesAudio();
    MilkdropView.debugPlaying = true;
  });

  test('пресетов столько же, сколько на ПК, имена уникальны', () {
    expect(mdPresets.length, 135);
    expect(mdPresets.map((p) => p.name).toSet().length, 135);
  });

  for (final name in [
    'off-axis tunnel',
    'lopsided vortex',
    'ember drift',
    'neon spiral slip',
    '[full] wave curtains',
    '[full] spectrum floor',
    '[full] plasma sea',
    '[full] lattice pulse',
  ]) {
    testWidgets('пресет $name', (t) async {
      t.view.physicalSize = const Size(300, 560);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.runAsync(MilkdropView.preload);
      final c = MilkdropController(start: mdPresets.indexWhere((p) => p.name == name));
      c.engine.mode = MdMode.lock;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: MilkdropView(controller: c))));
      for (var f = 0; f < 100; f++) {
        await t.pump(const Duration(milliseconds: 33)); // ~3 с: буфер наполняется «хвостами»
      }
      expect(c.name, name);
      final file = name.replaceAll(RegExp(r'[^a-z]+'), '_');
      await expectLater(find.byType(MilkdropView), matchesGoldenFile('goldens/md_$file.png'));
    }, tags: ['screenshots']);
  }

  testWidgets('слова текста — поверх MilkDrop', (t) async {
    t.view.physicalSize = const Size(300, 560);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(MilkdropView.preload);
    const tr = Track(id: 'md-text', title: 'Тест', artist: 'ECHOES', seconds: 60);
    audio.tracks.value = [tr];
    audio.index.value = 0;
    // своя тестовая строка (не текст настоящей песни)
    await t.runAsync(() => LyricsService.instance.save(
        tr,
        const Lyrics(
            [LyricLine(Duration.zero, 'привет это проверка слов'), LyricLine(Duration(seconds: 3), 'вторая строка')],
            true)));
    final c = MilkdropController(start: mdPresets.indexWhere((p) => p.name == 'off-axis tunnel'));
    c.engine.mode = MdMode.lock;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: MilkdropView(controller: c))));
    for (var f = 0; f < 10; f++) {
      await t.pump(const Duration(milliseconds: 33)); // слова вылетают поверх картинки
    }
    expect(find.byType(MilkdropWords), findsOneWidget);
    await expectLater(find.byType(MilkdropView), matchesGoldenFile('goldens/md_text.png'));
  }, tags: ['screenshots']);
}
