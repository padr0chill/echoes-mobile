// Интерфейс на разных экранах: iPhone SE … Pro Max, iPad, поворот. Переполнения и ошибки вёрстки валят тест.
import 'package:echoes_mobile/main.dart';
import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/screens/player_screen.dart';
import 'package:echoes_mobile/services/audio.dart';
import 'package:echoes_mobile/services/store.dart';
import 'package:echoes_mobile/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sizes = <String, Size>{
  'iPhone SE': Size(320, 568),
  'iPhone 15': Size(390, 844),
  'iPhone Pro Max': Size(430, 932),
  'iPhone landscape': Size(844, 390),
  'iPad': Size(1024, 1366),
  'iPad landscape': Size(1366, 1024),
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Store.instance.load();
    audio = EchoesAudio();
    final t = const Track(id: 'abc', title: 'Очень длинное название трека, которое не влезает', artist: 'Исполнитель', seconds: 215);
    Store.instance.toggleLike(t);
    Store.instance.createPlaylist('Тестовый плейлист');
    audio.tracks.value = [t, const Track(id: 'def', title: 'Второй', artist: 'Кто-то', seconds: 180)];
    audio.index.value = 0;
  });

  for (final e in sizes.entries) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('${e.key} text×$scale', (tester) async {
        tester.view.physicalSize = e.value * 3;
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(const EchoesApp());
        await tester.pump(const Duration(milliseconds: 300));
        for (final tab in ['Поиск', 'Для вас', 'Моя музыка', 'Профиль', 'Волна']) {
          await tester.tap(find.text(tab).last);
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: 'вкладка «$tab»');
        }
        // полный плеер
        await tester.tap(find.byType(MiniPlayer));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(PlayerScreen), findsOneWidget);
        await tester.tap(find.byTooltip('Текст песни'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
