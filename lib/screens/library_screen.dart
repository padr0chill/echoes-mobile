import 'package:flutter/material.dart';

import '../glass.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/offline.dart';
import '../services/store.dart';
import '../services/text_match.dart';
import '../ui.dart';
import '../widgets.dart';
import 'import_flow.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = Store.instance;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: st,
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(bottom: context.u(200)),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(context.u(16), context.u(16), context.u(16), 0),
              child: ScreenTitle('Моя музыка'),
            ),
            _Card(
              icon: Icons.favorite_rounded,
              title: 'Мне нравится',
              sub: '${st.liked.length} тр.',
              onTap: () => _open(context, 'Мне нравится', () => st.liked),
            ),
            ListenableBuilder(
              listenable: Offline.instance,
              builder: (context, _) => _Card(
                icon: Icons.download_done_rounded,
                title: 'Скачанное',
                sub: Offline.instance.count == 0
                    ? 'Играет без интернета — «Скачать» в меню трека'
                    : '${Offline.instance.count} тр. · ${fmtBytes(Offline.instance.bytes)}',
                onTap: () => _open(context, 'Скачанное', () => Offline.instance.tracks, offline: true),
              ),
            ),
            _Card(
              icon: Icons.computer_rounded,
              title: 'Импорт с ПК',
              sub: 'Плейлисты из ECHOES на компьютере',
              onTap: () => importFromPc(context),
            ),
            SectionTitle('Плейлисты',
                trailing: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () async {
                    final n = await askText(context, 'Новый плейлист', 'Название');
                    if (n != null) st.createPlaylist(n);
                  },
                )),
            if (st.playlists.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                child: const Text('Плейлистов пока нет — нажмите «+» или «Добавить в плейлист» у трека'),
              ),
            for (final p in st.playlists)
              _Card(
                icon: Icons.queue_music_rounded,
                title: p.name,
                sub: '${p.tracks.length} тр.',
                onTap: () => _open(context, p.name, () => p.tracks, playlist: p),
              ),
            if (st.history.isNotEmpty) const SectionTitle('Недавно играли'),
            for (var i = 0; i < st.history.length && i < 30; i++)
              TrackTile(track: st.history[i], onTap: () => audio.playList(st.history, i)),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, String title, List<Track> Function() tracks,
      {Playlist? playlist, bool offline = false}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackListScreen(title: title, tracks: tracks, playlist: playlist, offline: offline),
    ));
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _Card({required this.icon, required this.title, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(context.u(16), context.u(8), context.u(16), 0),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(context.r(22)),
        child: InkWell(
          borderRadius: BorderRadius.circular(context.r(22)),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(context.u(12)),
            child: Row(children: [
              Container(
                width: context.u(48),
                height: context.u(48),
                decoration: BoxDecoration(
                  color: context.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(context.r(14)),
                ),
                child: Icon(icon, color: context.accent),
              ),
              SizedBox(width: context.u(12)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(sub,
                      style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    );
  }
}

class TrackListScreen extends StatefulWidget {
  final String title;
  final List<Track> Function() tracks;
  final Playlist? playlist;
  final bool offline; // список «Скачанное»
  const TrackListScreen({super.key, required this.title, required this.tracks, this.playlist, this.offline = false});

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  final _q = TextEditingController();
  String _query = '';

  String get title => widget.title;
  List<Track> Function() get tracks => widget.tracks;
  Playlist? get playlist => widget.playlist;
  bool get offline => widget.offline;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// Поиск в плейлисте: все слова запроса есть в «название исполнитель» (без учёта регистра и
  /// транслитерации — «кишлак» найдёт и «Kishlak»).
  static String _norm(String s) => TextMatch.translit(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ');

  bool _match(Track t, List<String> words) {
    final hay = _norm('${t.title} ${t.artist}');
    final compact = hay.replaceAll(' ', '');
    return words.every((w) => hay.contains(w) || compact.contains(w));
  }

  @override
  Widget build(BuildContext context) {
    final st = Store.instance;
    return Ambient(
        child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(playlist?.name ?? title),
        actions: [
          if (playlist != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final n = await askText(context, 'Переименовать', 'Название', initial: playlist!.name);
                  if (n != null) st.renamePlaylist(playlist!, n);
                } else if (v == 'delete') {
                  st.deletePlaylist(playlist!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                PopupMenuItem(value: 'delete', child: Text('Удалить плейлист')),
              ],
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([st, Offline.instance]),
        builder: (context, _) {
          final list = tracks();
          if (list.isEmpty) {
            return const Center(child: Text('Пока пусто'));
          }
          final words = _norm(_query).split(' ').where((w) => w.isNotEmpty).toList();
          // индексы найденных треков в полном списке (играем весь плейлист — с выбранного трека)
          final shown = [
            for (var i = 0; i < list.length; i++)
              if (words.isEmpty || _match(list[i], words)) i
          ];
          final head = <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(8)),
              // кнопки делят ширину; на узком экране / крупном шрифте подпись ужимается, а не вылезает
              child: Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => audio.playList(list, 0),
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                    label: const FittedBox(
                        fit: BoxFit.scaleDown, child: Text('Слушать', style: TextStyle(color: Colors.black))),
                  ),
                ),
                SizedBox(width: context.u(8)),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      audio.shuffle.value = true; // список перемешает playList
                      audio.playList(list, DateTime.now().millisecondsSinceEpoch % list.length);
                    },
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Вперемешку')),
                  ),
                ),
                if (!offline) _DownloadAll(list: list),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(context.u(16), 0, context.u(16), context.u(6)),
              child: TextField(
                controller: _q,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Поиск в плейлисте',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _q.clear();
                            _query = '';
                          }),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(context.r(28)), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (words.isNotEmpty && shown.isEmpty)
              Padding(
                padding: EdgeInsets.all(context.u(24)),
                child: const Text('В этом плейлисте такого нет', textAlign: TextAlign.center),
              ),
          ];
          // список строится по мере прокрутки — быстро даже на 500+ треках
          return ListView.builder(
            padding: EdgeInsets.only(bottom: context.u(200)),
            itemCount: head.length + shown.length,
            itemBuilder: (context, k) {
              if (k < head.length) return head[k];
              final i = shown[k - head.length];
              return TrackTile(track: list[i], playlist: playlist, onTap: () => audio.playList(list, i));
            },
          );
        },
      ),
    ));
  }
}

/// «Скачать всё»: значок со счётчиком; когда всё скачано — галочка (нажатие — удалить загрузки списка).
class _DownloadAll extends StatelessWidget {
  final List<Track> list;
  const _DownloadAll({required this.list});

  @override
  Widget build(BuildContext context) {
    final o = Offline.instance;
    final done = list.where(o.has).length;
    final busy = list.where(o.busy).length;
    if (done == list.length) {
      return IconButton(
        tooltip: 'Скачано — удалить загрузки списка',
        icon: Icon(Icons.download_done_rounded, color: context.accent),
        onPressed: () => list.forEach(o.remove),
      );
    }
    if (busy > 0) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: context.u(8)),
        child: Text('$done/${list.length}', style: TextStyle(color: context.accent, fontWeight: FontWeight.w700)),
      );
    }
    return IconButton(
      tooltip: 'Скачать всё в приложение',
      icon: const Icon(Icons.download_rounded),
      onPressed: () {
        o.downloadAll(list);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Скачиваю ${list.length - done} тр. — потом будут играть без интернета')));
      },
    );
  }
}
