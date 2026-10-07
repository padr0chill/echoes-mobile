import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
import 'screens/for_you_screen.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/wave_screen.dart';
import 'services/audio.dart';
import 'services/offline.dart';
import 'services/sc.dart';
import 'services/store.dart';
import 'ui.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.instance.load();
  await Offline.instance.load();
  ScService.instance
    ..seedClientId(Store.instance.scClientId)
    ..onClientId = Store.instance.setScClientId;
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
    openTab.addListener(_onOpenTab);
  }

  @override
  void dispose() {
    audio.error.removeListener(_showError);
    openTab.removeListener(_onOpenTab);
    super.dispose();
  }

  void _onOpenTab() {
    final i = openTab.value;
    if (i == null) return;
    openTab.value = null;
    if (mounted) setState(() => _tab = i);
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
    // скрытые вкладки не анимируются (волна не крутит шейдер, пока вы в поиске)
    final body = IndexedStack(index: _tab, children: [
      for (var i = 0; i < _pages.length; i++) TickerMode(enabled: i == _tab, child: _pages[i]),
    ]);
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
      return Ambient(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Row(children: [
            SafeArea(
              right: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Glass(
                  radius: 28,
                  tint: 1.2,
                  child: NavigationRail(
                    backgroundColor: Colors.transparent,
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
                ),
              ),
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
        ),
      );
    }
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: BackdropGroup(
            child: Stack(children: [
          Positioned.fill(child: body),
          // плавающие мини-плеер и панель вкладок — стекло поверх содержимого
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              mini,
              GlassTabBar(items: items, index: _tab, onTap: (i) => setState(() => _tab = i)),
            ]),
          ),
        ])),
      ),
    );
  }
}

/// Нижняя панель вкладок — стеклянная капсула; «линза» плавно переезжает под выбранную вкладку.
class GlassTabBar extends StatelessWidget {
  final List<(IconData, String)> items;
  final int index;
  final ValueChanged<int> onTap;
  const GlassTabBar({super.key, required this.items, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final h = context.u(62);
    return Padding(
      padding: EdgeInsets.fromLTRB(context.u(12), 0, context.u(12), bottom > 0 ? bottom : context.u(10)),
      child: Glass(
        radius: h / 2,
        tint: 1.3,
        child: SizedBox(
          height: h,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth / items.length;
            return Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutBack,
                left: index * w + 4,
                width: w - 8,
                top: 5,
                bottom: 5,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(h / 2),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withValues(alpha: 0.26), Colors.white.withValues(alpha: 0.08)],
                    ),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
                  ),
                ),
              ),
              Row(children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      label: items[i].$2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTap(i),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedScale(
                            scale: i == index ? 1.12 : 1.0,
                            duration: const Duration(milliseconds: 250),
                            child: Icon(items[i].$1, size: context.u(23), color: i == index ? context.accent : null),
                          ),
                          SizedBox(height: context.u(2)),
                          Text(items[i].$2,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: i == index ? FontWeight.w800 : FontWeight.w500,
                                color: i == index ? context.accent : null,
                              )),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}
