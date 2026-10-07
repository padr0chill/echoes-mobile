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
import '../i18n.dart';

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
              child: ScreenTitle(tr('Моя музыка')),
            ),
            _Card(
              icon: Icons.favorite_rounded,
              title: tr('Мне нравится'),
              sub: tr('{0} тр.', [st.liked.length]),
              onTap: () => _open(context, tr('Мне нравится'), () => st.liked),
            ),
            ListenableBuilder(
              listenable: Offline.instance,
              builder: (context, _) => _Card(
                icon: Icons.download_done_rounded,
                title: tr('Скачанное'),
                sub: Offline.instance.count == 0
                    ? tr('Играет без интернета — «Скачать» в меню трека')
                    : tr('{0} тр. · {1}', [Offline.instance.count, fmtBytes(Offline.instance.bytes)]),
                onTap: () => _open(context, tr('Скачанное'), () => Offline.instance.tracks, offline: true),
              ),
            ),
            _Card(
              icon: Icons.computer_rounded,
              title: tr('Импорт с ПК'),
              sub: tr('Плейлисты из ECHOES на компьютере'),
              onTap: () => importFromPc(context),
            ),
            SectionTitle(tr('Плейлисты'),
                trailing: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () async {
                    final n = await askText(context, tr('Новый плейлист'), tr('Название'));
                    if (n != null) st.createPlaylist(n);
                  },
                )),
            if (st.playlists.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                child: Text(tr('Плейлистов пока нет — нажмите «+» или «Добавить в плейлист» у трека')),
              ),
            for (final p in st.playlists)
              _Card(
                icon: Icons.queue_music_rounded,
                title: p.name,
                sub: tr('{0} тр.', [p.tracks.length]),
                onTap: () => _open(context, p.name, () => p.tracks, playlist: p),
              ),
            if (st.history.isNotEmpty) SectionTitle(tr('Недавно играли')),
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

  static List<(String, IconData, String)> get _sorts => [
        ('order', Icons.south_rounded, tr('Как добавлены (сверху вниз)')),
        ('recent', Icons.north_rounded, tr('Сначала новые (снизу вверх)')),
        ('title', Icons.sort_by_alpha_rounded, tr('По названию (А → Я)')),
        ('artist', Icons.person_rounded, tr('По исполнителю')),
        ('duration', Icons.timer_outlined, tr('По длительности')),
      ];

  /// Порядок показа (и игры — играет то, что видно): как добавлены / наоборот / по названию / исполнителю /
  /// длительности. Сравнение названий — без регистра.
  static List<Track> _sorted(List<Track> l, String mode) {
    int byText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    switch (mode) {
      case 'recent':
        return l.reversed.toList();
      case 'title':
        return [...l]..sort((a, b) => byText(a.title, b.title));
      case 'artist':
        return [...l]..sort((a, b) {
            final c = byText(a.artist, b.artist);
            return c != 0 ? c : byText(a.title, b.title);
          });
      case 'duration':
        return [...l]..sort((a, b) => a.seconds.compareTo(b.seconds));
      default:
        return l;
    }
  }

  Future<void> _pickSort(BuildContext context) async {
    final st = Store.instance;
    await showGlassSheet<void>(
      context,
      (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (k, icon, label) in _sorts)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: st.playlistSort == k ? Icon(Icons.check_rounded, color: ctx.accent) : null,
              onTap: () {
                st.setPlaylistView(sort: k);
                Navigator.pop(ctx);
              },
            ),
        ]),
      ),
    );
  }

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
          IconButton(
            tooltip: tr('Порядок'),
            icon: const Icon(Icons.sort_rounded),
            onPressed: () => _pickSort(context),
          ),
          ListenableBuilder(
            listenable: st,
            builder: (context, _) => IconButton(
              tooltip: st.playlistGrid ? tr('Списком') : tr('Сеткой'),
              icon: Icon(st.playlistGrid ? Icons.view_list_rounded : Icons.grid_view_rounded),
              onPressed: () => st.setPlaylistView(grid: !st.playlistGrid),
            ),
          ),
          if (playlist != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final n = await askText(context, tr('Переименовать'), tr('Название'), initial: playlist!.name);
                  if (n != null) st.renamePlaylist(playlist!, n);
                } else if (v == 'delete') {
                  st.deletePlaylist(playlist!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'rename', child: Text(tr('Переименовать'))),
                PopupMenuItem(value: 'delete', child: Text(tr('Удалить плейлист'))),
              ],
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([st, Offline.instance]),
        builder: (context, _) {
          final list = _sorted(tracks(), st.playlistSort);
          if (list.isEmpty) {
            return Center(child: Text(tr('Пока пусто')));
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
                    label: FittedBox(
                        fit: BoxFit.scaleDown, child: Text(tr('Слушать'), style: TextStyle(color: Colors.black))),
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
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Вперемешку'))),
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
                  hintText: tr('Поиск в плейлисте'),
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
                child: Text(tr('В этом плейлисте такого нет'), textAlign: TextAlign.center),
              ),
          ];
          // список строится по мере прокрутки — быстро даже на 500+ треках
          if (st.playlistGrid) {
            // сетка обложек слева направо: столбцов — сколько влезает (2 на телефоне, больше на iPad)
            return LayoutBuilder(builder: (context, box) {
              final cols = (box.maxWidth / context.u(180)).floor().clamp(2, 6);
              final rows = (shown.length + cols - 1) ~/ cols;
              return ListView.builder(
                padding: EdgeInsets.only(bottom: context.u(200)),
                itemCount: head.length + rows,
                itemBuilder: (context, k) {
                  if (k < head.length) return head[k];
                  final r = k - head.length;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(context.u(16), 0, context.u(16), context.u(14)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (var c = 0; c < cols; c++) ...[
                        if (c > 0) SizedBox(width: context.u(12)),
                        Expanded(
                          child: r * cols + c < shown.length
                              ? _GridTrack(
                                  track: list[shown[r * cols + c]],
                                  playlist: playlist,
                                  onTap: () => audio.playList(list, shown[r * cols + c]),
                                )
                              : const SizedBox(),
                        ),
                      ],
                    ]),
                  );
                },
              );
            });
          }
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
        tooltip: tr('Скачано — удалить загрузки списка'),
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
      tooltip: tr('Скачать всё в приложение'),
      icon: const Icon(Icons.download_rounded),
      onPressed: () {
        o.downloadAll(list);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Скачиваю {0} тр. — потом будут играть без интернета', [list.length - done]))));
      },
    );
  }
}

/// Плитка трека в сетке: обложка, название, исполнитель; долгое нажатие — меню трека.
class _GridTrack extends StatelessWidget {
  final Track track;
  final Playlist? playlist;
  final VoidCallback onTap;
  const _GridTrack({required this.track, required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cur = audio.current == track;
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => showTrackMenu(context, track, playlist: playlist),
      child: LayoutBuilder(
        builder: (context, box) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Cover(track: track, size: box.maxWidth, radius: context.r(14)),
          SizedBox(height: context.u(6)),
          Text(track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: cur ? context.accent : null)),
          Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: dim)),
        ]),
      ),
    );
  }
}
