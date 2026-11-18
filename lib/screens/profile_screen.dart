import 'package:flutter/material.dart';

import '../glass.dart';
import '../services/store.dart';
import '../skins/phantom.dart';
import '../ui.dart';
import '../widgets.dart';
import 'net_screen.dart';
import 'settings_screen.dart';
import '../i18n.dart';

/// Профиль: имя, статистика прослушиваний, любимые исполнители; настройки — отсюда.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _time(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return h > 0 ? tr('{0} ч {1} мин', [h, m]) : tr('{0} мин', [m]);
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
          Future<void> rename() async {
            final n = await askText(context, tr('Ваше имя'), tr('Имя'), initial: st.name);
            if (n != null) st.setName(n);
          }

          return ListView(
            padding: EdgeInsets.only(bottom: context.pageEnd(200)),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(context.u(16), context.u(16), context.u(8), 0),
                child: Row(
                  children: [
                    Expanded(child: ScreenTitle(tr('Профиль'))),
                    IconButton(
                      tooltip: tr('Настройки'),
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => Ambient(
                            child: Scaffold(
                              backgroundColor: Colors.transparent,
                              appBar: AppBar(backgroundColor: context.phantom ? Colors.transparent : null),
                              body: const SettingsScreen(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: context.u(12)),
              if (context.phantom)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                  child: PhantomPanel(
                    radius: 16,
                    solid: true,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox.square(
                          dimension: 48,
                          child: PhantomArtworkPlaceholder(size: 48, title: st.name),
                        ),
                      ),
                      title: Text(
                        tr(st.name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -.4),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: rename,
                    ),
                  ),
                )
              else ...[
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
                    onTap: rename,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tr(st.name), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 6),
                          Icon(Icons.edit_rounded, size: 18, color: context.accent),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              SizedBox(height: context.u(16)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('ECHOES.NET'),
                    subtitle: Text(tr('Публичная лента и профиль с ПК')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NetScreen())),
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
                    _Stat(tr('Время с музыкой'), _time(st.listenSeconds), Icons.schedule_rounded),
                    _Stat(tr('Включено треков'), '${st.plays}', Icons.play_circle_rounded),
                    _Stat(tr('Разных треков'), '${st.listenedIds.length}', Icons.library_music_rounded),
                    _Stat(tr('Мне нравится'), '${st.liked.length}', Icons.favorite_rounded),
                  ],
                ),
              ),
              SectionTitle(tr('Любимые исполнители')),
              if (top.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                  child: Text(tr('Появятся, когда вы что-нибудь послушаете')),
                ),
              for (var i = 0; i < top.length; i++)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(6)),
                  child: Row(
                    children: [
                      SizedBox(
                        width: context.u(26),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(fontWeight: FontWeight.w900, color: context.accent),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              top[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
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
                          ],
                        ),
                      ),
                      SizedBox(width: context.u(10)),
                      Text(
                        _time(st.artistSeconds[top[i]] ?? 0),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: context.u(12)),
              ListTile(
                leading: const Icon(Icons.history_toggle_off_rounded),
                title: Text(tr('Очистить историю')),
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(tr('Очистить историю?')),
                    content: Text(tr('«Недавно играли» и подборки начнутся заново. Лайки и плейлисты останутся.')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Отмена'))),
                      FilledButton(
                        onPressed: () {
                          st.clearHistory();
                          Navigator.pop(ctx);
                        },
                        child: Text(tr('Очистить')),
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
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(context.r(context.phantom ? 12 : 20)),
        border: context.phantom ? Border.all(color: Phantom.line) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}
