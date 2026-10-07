import 'package:echoes_mobile/screens/album_screen.dart';
import 'package:echoes_mobile/services/sc.dart';
import 'package:echoes_mobile/services/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Лента альбомов (страница исполнителя, поиск) не переполняется на разных экранах и с крупным шрифтом.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.load();
  });

  final albums = [
    for (var i = 0; i < 6; i++)
      ScAlbum(i, 'Очень длинное название альбома номер $i (Deluxe Edition)', 'LINKIN PARK', 1, null, 12, 2024,
          i.isEven ? 'album' : 'single'),
  ];

  for (final size in const [Size(320, 568), Size(390, 844), Size(1024, 1366)]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('album row ${size.width.toInt()} text×$scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: ListView(children: [AlbumRow(albums: albums), AlbumRow(albums: albums, showArtist: true)]),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
