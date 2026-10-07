import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/for_you_screen.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/wave_screen.dart';
import 'services/audio.dart';
import 'services/store.dart';
import 'ui.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.load();
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  audio = await AudioService.init(
    builder: () => EchoesAudio(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.echoes.mobile.audio',
      androidNotificationChannelName: 'ECHOES',
      androidNotificationOngoing: true,
    ),
  );
  runApp(const EchoesApp());
}

class EchoesApp extends StatelessWidget {
  const EchoesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.instance,
      builder: (context, _) {
        final st = Store.instance;
        return MaterialApp(
          title: 'ECHOES',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(st.accent, st.light),
          // текст растёт вместе с экраном (iPad), системный «крупный шрифт» — не больше ×1.3
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final sys = mq.textScaler.scale(1.0).clamp(0.9, 1.3);
            final short = math.min(mq.size.width, mq.size.height);
            final k = (short / 390).clamp(0.85, 1.35);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(sys * k)),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: st.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
                child: child!,
              ),
            );
          },
          home: const Shell(),
        );
      },
    );
  }
}

/// Нижняя панель (телефон) или боковая (iPad / поворот), мини-плеер над ней.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  static const _pages = [WaveScreen(), SearchScreen(), ForYouScreen(), LibraryScreen(), ProfileScreen()];

  @override
  void initState() {
    super.initState();
    audio.error.addListener(_showError); // ошибка трека — сразу видно, с причиной
  }

  @override
  void dispose() {
    audio.error.removeListener(_showError);
    super.dispose();
  }

  void _showError() {
    final e = audio.error.value;
    if (e == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e), duration: const Duration(seconds: 6)));
  }

  void _openPlayer() {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => const PlayerScreen(),
      transitionsBuilder: (_, a, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(index: _tab, children: _pages);
    final mini = MiniPlayer(onOpen: _openPlayer);
    const items = [
      (Icons.waves_rounded, 'Волна'),
      (Icons.search_rounded, 'Поиск'),
      (Icons.auto_awesome_rounded, 'Для вас'),
      (Icons.library_music_rounded, 'Моя музыка'),
      (Icons.person_rounded, 'Профиль'),
    ];
    if (context.wide) {
      // невысокий экран (телефон боком) — только значки, без подписей и логотипа
      final low = MediaQuery.sizeOf(context).height < 560;
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: low ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: low
                ? null
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Icon(Icons.graphic_eq_rounded, color: context.accent, size: 32),
                  ),
            destinations: [
              for (final it in items) NavigationRailDestination(icon: Icon(it.$1), label: Text(it.$2)),
            ],
          ),
          Expanded(
            // на iPad содержимое не растягивается на всю ширину — колонка по центру
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Stack(children: [
                  Positioned.fill(child: body),
                  Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(top: false, child: mini)),
                ]),
              ),
            ),
          ),
        ]),
      );
    }
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: body),
        Positioned(left: 0, right: 0, bottom: 0, child: mini),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        height: context.u(64),
        destinations: [for (final it in items) NavigationDestination(icon: Icon(it.$1), label: it.$2)],
      ),
    );
  }
}
