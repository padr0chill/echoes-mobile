import 'package:echoes_mobile/services/audio.dart';
import 'package:echoes_mobile/services/store.dart';
import 'package:echoes_mobile/skins/milkdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Пресеты MilkDrop по очереди (скриншоты): flutter test test/milkdrop_test.dart --run-skipped --update-goldens
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.load();
    audio = EchoesAudio();
  });
  testWidgets('все пресеты переключаются нажатием', (t) async {
    t.view.physicalSize = const Size(390, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(MilkdropView.preload);
    await t.pumpWidget(const MaterialApp(home: MilkdropScreen()));
    for (var i = 0; i < milkdropPresets.length; i++) {
      if (i > 0) await t.tapAt(const Offset(195, 400));
      for (var f = 0; f < 60; f++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.textContaining(milkdropPresets[i].split(' — ').first), findsOneWidget);
      await expectLater(find.byType(MilkdropView), matchesGoldenFile('goldens/milkdrop_preset_$i.png'));
    }
  }, tags: ['screenshots']);
}
