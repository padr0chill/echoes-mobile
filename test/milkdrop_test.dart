import 'package:echoes_mobile/services/audio.dart';
import 'package:echoes_mobile/services/store.dart';
import 'package:echoes_mobile/skins/milkdrop.dart';
import 'package:echoes_mobile/skins/milkdrop_engine.dart';
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
}
