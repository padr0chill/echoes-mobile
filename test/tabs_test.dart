// Экраны внутри вкладки (плейлист, исполнитель, альбом) не закрывают мини-плеер и панель вкладок.
import 'package:echoes_mobile/main.dart';
import 'package:echoes_mobile/models.dart';
import 'package:echoes_mobile/screens/library_screen.dart';
import 'package:echoes_mobile/services/audio.dart';
import 'package:echoes_mobile/services/store.dart';
import 'package:echoes_mobile/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.load();
    audio = EchoesAudio();
    const a = Track(id: 'aaa', title: 'Первый', artist: 'Кто-то', seconds: 120);
    const b = Track(id: 'bbb', title: 'Второй', artist: 'Кто-то', seconds: 130);
    final p = Store.instance.createPlaylist('груз 200');
    Store.instance.addToPlaylist(p, a);
    Store.instance.addToPlaylist(p, b);
    audio.tracks.value = [a, b];
    audio.index.value = 0;
  });

  testWidgets('плейлист открыт — мини-плеер и вкладки видны; повторное нажатие вкладки — назад', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(const EchoesApp());
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Моя музыка').last);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('груз 200'));
    await t.pumpAndSettle();

    expect(find.byType(TrackListScreen), findsOneWidget);
    expect(find.byType(MiniPlayer).hitTestable(), findsOneWidget);
    expect(find.byType(GlassTabBar).hitTestable(), findsOneWidget);
    // мини-плеер не перекрыт: его название трека видно поверх списка
    expect(find.descendant(of: find.byType(MiniPlayer), matching: find.text('Первый')).hitTestable(), findsOneWidget);

    // другая вкладка и обратно — плейлист на месте (у вкладки свой стек)
    await t.tap(find.text('Поиск').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Моя музыка').last);
    await t.pumpAndSettle();
    expect(find.byType(TrackListScreen), findsOneWidget);

    // ещё раз на ту же вкладку — к её началу
    await t.tap(find.text('Моя музыка').last);
    await t.pumpAndSettle();
    expect(find.byType(TrackListScreen), findsNothing);
    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('поиск в плейлисте: находит без учёта регистра, играет весь плейлист с найденного', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(const EchoesApp());
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Моя музыка').last);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('груз 200'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Поиск в плейлисте'), 'ВТОР');
    await t.pump();
    final tiles = find.descendant(of: find.byType(TrackListScreen), matching: find.byType(TrackTile));
    expect(tiles, findsOneWidget);
    expect(find.descendant(of: tiles, matching: find.text('Второй')), findsOneWidget);
    await t.tap(find.descendant(of: tiles, matching: find.text('Второй')));
    await t.pump();
    expect(audio.tracks.value.length, 2); // весь плейлист, а не только найденное
    expect(audio.index.value, 1); // с найденного трека
    await t.enterText(find.widgetWithText(TextField, 'Поиск в плейлисте'), 'нет такого');
    await t.pump();
    expect(find.text('В этом плейлисте такого нет'), findsOneWidget);
  });

  testWidgets('порядок плейлиста и сетка обложек', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    addTearDown(() => Store.instance.setPlaylistView(sort: 'order', grid: false));
    await t.pumpWidget(const EchoesApp());
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Моя музыка').last);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('груз 200'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    double y(String s) => t.getTopLeft(find.descendant(of: find.byType(TrackListScreen), matching: find.text(s))).dy;
    expect(y('Первый') < y('Второй'), isTrue); // как добавлены
    await t.tap(find.byTooltip('Порядок'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    await t.tap(find.text('По названию (А → Я)'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    expect(y('Второй') < y('Первый'), isTrue); // «В» раньше «П»
    await t.tap(find.byTooltip('Сеткой'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    expect(find.descendant(of: find.byType(TrackListScreen), matching: find.byType(TrackTile)), findsNothing);
    // в сетке — рядом, слева направо
    final a = t.getTopLeft(find.descendant(of: find.byType(TrackListScreen), matching: find.text('Второй')));
    final b = t.getTopLeft(find.descendant(of: find.byType(TrackListScreen), matching: find.text('Первый')));
    expect((a.dy - b.dy).abs() < 1 && a.dx < b.dx, isTrue);
  });
}
