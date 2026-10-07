// Свайпы по треку, как в Spotify: вправо — в очередь, влево — выбор плейлиста; короткий свайп — ничего.
import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/services/audio.dart';
import 'package:echoes_mobile/services/store.dart';
import 'package:echoes_mobile/ui.dart';
import 'package:echoes_mobile/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const t = Track(id: 'swp', title: 'Свайп-трек', artist: 'Исполнитель', seconds: 200);
  const other = Track(id: 'oth', title: 'Играет', artist: 'Кто-то', seconds: 180);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.load();
    audio = EchoesAudio();
    audio.tracks.value = [other];
    audio.index.value = 0;
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Store.instance.accent, false),
      home: Scaffold(body: ListView(children: [TrackTile(track: t, onTap: () {})])),
    ));
  }

  testWidgets('вправо — в очередь', (tester) async {
    await pump(tester);
    await tester.drag(find.byType(TrackTile), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(audio.tracks.value.map((x) => x.id), contains('swp'));
    expect(find.textContaining('в очереди'), findsOneWidget);
  });

  testWidgets('влево — выбор плейлиста', (tester) async {
    await pump(tester);
    await tester.drag(find.byType(TrackTile), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(find.text('Новый плейлист'), findsOneWidget);
  });

  testWidgets('короткий свайп — ничего, строка возвращается', (tester) async {
    audio.tracks.value = [other];
    await pump(tester);
    await tester.drag(find.byType(TrackTile), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(audio.tracks.value.length, 1);
    expect(find.text('Новый плейлист'), findsNothing);
    final tr =
        tester.widget<Transform>(find.descendant(of: find.byType(SwipeActions), matching: find.byType(Transform)).last);
    expect(tr.transform.getTranslation().x, 0);
  });
}
