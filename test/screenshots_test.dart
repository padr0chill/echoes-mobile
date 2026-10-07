// Снимки экранов для просмотра (не проверка): flutter test test/screenshots_test.dart --update-goldens
// Картинки — в test/goldens/. Шрифты — Roboto из Flutter SDK, обложки — из папки COVERS_DIR.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:echoes_mobile/main.dart';
import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/cover_color.dart';
import 'package:echoes_mobile/services/audio.dart';
import 'package:echoes_mobile/services/wave.dart';
import 'package:echoes_mobile/services/store.dart';
import 'package:echoes_mobile/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? r'F:\ZHOPA\flutter';
  final dir = '$sdk/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String n) async => ByteData.sublistView(await File('$dir/$n').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final n in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
    if (File('$dir/$n').existsSync()) roboto.addFont(f(n));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(f('materialicons-regular.otf'));
  await icons.load();
}

const tracks = [
  Track(id: 'a', title: 'Numb', artist: 'Linkin Park', seconds: 186),
  Track(id: 'b', title: 'Kosandra', artist: 'Miyagi & Andy Panda', seconds: 221),
  Track(id: 'c', title: 'blessed', artist: 'zxcursed', seconds: 124),
  Track(id: 'd', title: 'Иуда', artist: 'N0IR', seconds: 90),
  Track(id: 'e', title: 'Исчезай ты', artist: 'PLOHOYPAREN', seconds: 140),
  Track(id: 'f', title: 'In the End', artist: 'Linkin Park', seconds: 216),
  Track(id: 'g', title: 'Blinding Lights', artist: 'The Weeknd', seconds: 200),
];

void main() {
  final images = <String, ImageProvider>{};

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Store.instance.load();
    final cov = Directory(Platform.environment['COVERS_DIR'] ?? '');
    final files = cov.existsSync()
        ? (cov.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];
    for (var i = 0; i < tracks.length && files.isNotEmpty; i++) {
      images[tracks[i].id] = MemoryImage(files[(i * 37) % files.length].readAsBytesSync());
    }
    if (images.isNotEmpty) Cover.debugImage = (t) => images[t.id] ?? images.values.first;
    audio = EchoesAudio();
    for (final t in tracks.reversed) {
      Store.instance.addHistory(t);
    }
    Store.instance.setName('Игорь');
    for (final t in tracks) {
      Store.instance.addListened(t, 600 + t.seconds * 3);
    }
    Store.instance.toggleLike(tracks[0]);
    Store.instance.toggleLike(tracks[2]);
    Store.instance.addToPlaylist(Store.instance.createPlaylist('В дорогу'), tracks[1]);
    Store.instance.addToPlaylist(Store.instance.createPlaylist('Ночь'), tracks[3]);
    for (final q in ['linkin park', 'miyagi', 'zxcursed blessed']) {
      Store.instance.addSearch(q);
    }
    audio.tracks.value = tracks;
    audio.index.value = 1;
  });

  Future<void> shoot(WidgetTester tester, Size size, String name, Future<void> Function() go) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(const EchoesApp());
      for (final img in images.values) {
        final ctx = tester.element(find.byType(Scaffold).first);
        await precacheImage(img, ctx);
        // маленькие копии для размытого фона (плеер, «атмосфера»)
        for (final s in [12, 14]) {
          await precacheImage(ResizeImage(img, width: s, height: s, policy: ResizeImagePolicy.fit), ctx);
        }
      }
    });
    await tester.pump(const Duration(milliseconds: 300));
    await go();
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openPlayer(WidgetTester tester) async {
    await tester.tap(find.byType(MiniPlayer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  const phone = Size(390, 844);
  const se = Size(320, 568);
  const pad = Size(1024, 1366);
  const padLand = Size(1366, 1024);

  testWidgets('phone library', (t) => shoot(t, phone, 'phone_library', () => openTab(t, 'Моя музыка')));
  testWidgets('phone profile', (t) => shoot(t, phone, 'phone_profile', () => openTab(t, 'Профиль')));
  testWidgets('phone wave', (t) => shoot(t, phone, 'phone_wave', () async {}));
  testWidgets('phone wave playing', (t) async {
    await t.runAsync(() => coverColor(audio.current!)); // цвет обложки — заранее (в тесте нет фоновой загрузки)
    audio.nearEnd = Wave.instance.extend;
    addTearDown(() => audio.nearEnd = null);
    await shoot(t, phone, 'phone_wave_playing', () => t.pump(const Duration(milliseconds: 1600)));
  });
  testWidgets('phone vinyl', (t) async {
    Store.instance.setVinyl(true);
    addTearDown(() => Store.instance.setVinyl(false));
    await shoot(t, phone, 'phone_vinyl', () => openPlayer(t));
  });
  testWidgets('phone queue', (t) async {
    audio.addToQueue(audio.tracks.value.last);
    await shoot(t, phone, 'phone_queue', () async {
      await openPlayer(t);
      await t.tap(find.byTooltip('Очередь'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
    });
  });
  testWidgets('winamp player', (t) async {
    Store.instance.setSkin('winamp');
    addTearDown(() => Store.instance.setSkin('glass'));
    await shoot(t, phone, 'winamp_player', () => openPlayer(t));
  });
  testWidgets('winamp library', (t) async {
    Store.instance.setSkin('winamp');
    addTearDown(() => Store.instance.setSkin('glass'));
    await shoot(t, phone, 'winamp_library', () => openTab(t, 'Моя музыка'));
  });
  testWidgets('phone search', (t) => shoot(t, phone, 'phone_search', () => openTab(t, 'Поиск')));
  testWidgets('phone player', (t) => shoot(t, phone, 'phone_player', () => openPlayer(t)));
  testWidgets('se library', (t) => shoot(t, se, 'se_library', () => openTab(t, 'Моя музыка')));
  testWidgets('se player', (t) => shoot(t, se, 'se_player', () => openPlayer(t)));
  testWidgets('ipad library', (t) => shoot(t, pad, 'ipad_library', () => openTab(t, 'Моя музыка')));
  testWidgets('ipad landscape player', (t) => shoot(t, padLand, 'ipad_land_player', () => openPlayer(t)));
}
