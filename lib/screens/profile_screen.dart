import 'package:flutter/material.dart';

import '../glass.dart';
import '../services/store.dart';
import '../ui.dart';
import '../widgets.dart';
import 'settings_screen.dart';

/// Профиль: имя, статистика прослушиваний, любимые исполнители; настройки — отсюда.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _time(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return h > 0 ? '$h ч $m мин' : '$m мин';
  }

  @override
  Widget build(BuildContext context) {
    final st = Store.instance;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: st,
        builder: (context, _) {
          final top = st.topArtists(5);
          final maxS = top.isEmpty ? 1 : (st.artistSeconds[top.first] ?? 1);
          return ListView(
            padding: EdgeInsets.only(bottom: context.u(200)),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(context.u(16), context.u(16), context.u(8), 0),
                child: Row(children: [
                  const Expanded(child: Text('Профиль', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900))),
                  IconButton(
                    tooltip: 'Настройки',
                    icon: const Icon(Icons.settings_rounded),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => Ambient(
                        child: Scaffold(
                            backgroundColor: Colors.transparent, appBar: AppBar(), body: const SettingsScreen()),
                      ),
                    )),
                  ),
                ]),
              ),
              SizedBox(height: context.u(12)),
              Center(
                child: CircleAvatar(
                  radius: context.u(46),
                  backgroundColor: context.accent,
                  child: Text(
                    st.name.isEmpty ? '?' : st.name.characters.first.toUpperCase(),
                    style: TextStyle(fontSize: context.u(40), fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ),
              ),
              SizedBox(height: context.u(10)),
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.r(12)),
                  onTap: () async {
                    final n = await askText(context, 'Ваше имя', 'Имя', initial: st.name);
                    if (n != null) st.setName(n);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(st.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_rounded, size: 18, color: context.accent),
                    ]),
                  ),
                ),
              ),
              SizedBox(height: context.u(16)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                child: GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // высота — по реальному размеру шрифта (крупный системный шрифт не обрезается)
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: context.wide ? 4 : 2,
                    mainAxisSpacing: context.u(10),
                    crossAxisSpacing: context.u(10),
                    mainAxisExtent: context.u(24) + MediaQuery.textScalerOf(context).scale(1) * 60,
                  ),
                  children: [
                    _Stat('Время с музыкой', _time(st.listenSeconds), Icons.schedule_rounded),
                    _Stat('Включено треков', '${st.plays}', Icons.play_circle_rounded),
                    _Stat('Разных треков', '${st.listenedIds.length}', Icons.library_music_rounded),
                    _Stat('Мне нравится', '${st.liked.length}', Icons.favorite_rounded),
                  ],
                ),
              ),
              const SectionTitle('Любимые исполнители'),
              if (top.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                  child: const Text('Появятся, когда вы что-нибудь послушаете'),
                ),
              for (var i = 0; i < top.length; i++)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(6)),
                  child: Row(children: [
                    SizedBox(
                      width: context.u(26),
                      child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: context.accent)),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(top[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: context.u(4)),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (st.artistSeconds[top[i]] ?? 0) / maxS,
                            minHeight: 5,
                            color: context.accent,
                            backgroundColor: context.accent.withValues(alpha: 0.12),
                          ),
                        ),
                      ]),
                    ),
                    SizedBox(width: context.u(10)),
                    Text(_time(st.artistSeconds[top[i]] ?? 0),
                        style: TextStyle(
                            fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
                  ]),
                ),
              SizedBox(height: context.u(12)),
              ListTile(
                leading: const Icon(Icons.history_toggle_off_rounded),
                title: const Text('Очистить историю'),
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Очистить историю?'),
                    content: const Text('«Недавно играли» и подборки начнутся заново. Лайки и плейлисты останутся.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
                      FilledButton(
                        onPressed: () {
                          st.clearHistory();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Очистить'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Stat(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.u(12)),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(context.r(20))),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          Icon(icon, size: 18, color: context.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7))),
          ),
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }
}
