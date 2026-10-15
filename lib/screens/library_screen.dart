import 'package:flutter/material.dart';

import '../glass.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/offline.dart';
import '../services/store.dart';
import '../services/text_match.dart';
import '../ui.dart';
import '../widgets.dart';
import 'artist_screen.dart';
import 'games.dart';
import 'import_flow.dart';
import '../playlist_art.dart';
import '../i18n.dart';

/// «Моя музыка» как медиатека Spotify: закреплённые «Мне нравится» и «Скачанное», фильтр «Плейлисты /
/// Исполнители», сортировка (свой порядок — перетаскиванием, недавние, по алфавиту), список или сетка обложек.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String? _filter; // null — всё, 'pl' — плейлисты, 'ar' — исполнители

  static const _sorts = {'custom': 'Свой порядок', 'recent': 'Недавние', 'alpha': 'По алфавиту'};

  List<Playlist> _sorted(Store st) {
    final l = [...st.playlists];
    switch (st.librarySort) {
      case 'recent':
        l.sort((a, b) => b.touched.compareTo(a.touched));
      case 'alpha':
        l.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return l;
  }

  void _open(BuildContext context, String title, List<Track> Function() tracks,
      {Playlist? playlist, bool offline = false}) {
    if (playlist != null) Store.instance.touchPlaylist(playlist);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackListScreen(title: title, tracks: tracks, playlist: playlist, offline: offline),
    ));
  }

  Future<void> _add(BuildContext context) async {
    final v = await showGlassSheet<String>(
      context,
      (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: Text(tr('Новый плейлист')),
            onTap: () => Navigator.pop(ctx, 'new'),
          ),
          ListTile(
            leading: const Icon(Icons.computer_rounded),
            title: Text(tr('Импорт с ПК')),
            subtitle: Text(tr('Плейлисты из ECHOES на компьютере')),
            onTap: () => Navigator.pop(ctx, 'import'),
          ),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (v == 'new') {
      final n = await askText(context, tr('Новый плейлист'), tr('Название'));
      if (n != null) Store.instance.createPlaylist(n);
    } else if (v == 'import') {
      importFromPc(context);
    }
  }

  Future<void> _pickSort(BuildContext context) async {
    final st = Store.instance;
    final v = await showGlassSheet<String>(
      context,
      (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.all(ctx.u(14)),
            child: Text(tr('Сортировка'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final e in _sorts.entries)
            ListTile(
              title: Text(tr(e.value)),
              subtitle: e.key == 'custom' ? Text(tr('Удерживайте плейлист и перетащите')) : null,
              trailing: st.librarySort == e.key ? Icon(Icons.check_rounded, color: ctx.accent) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ]),
      ),
    );
    if (v != null) st.setLibraryView(sort: v);
  }

  @override
  Widget build(BuildContext context) {
    final st = Store.instance;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([st, Offline.instance]),
        builder: (context, _) {
          final pls = _sorted(st);
          final artists = _filter == 'pl' ? <String>[] : st.topArtists(12);
          final showPl = _filter != 'ar';
          final grid = st.libraryGrid;
          final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
          // закреплённые сверху (как «Понравившиеся треки» в Spotify)
          final pinned = <_Item>[
            if (showPl)
              _Item(
                title: tr('Мне нравится'),
                sub: tr('Плейлист • {0}', [
                  tr('{0} тр.', [st.liked.length])
                ]),
                art: (s) => _Gradient(size: s, icon: Icons.favorite_rounded),
                onTap: () => _open(context, tr('Мне нравится'), () => st.liked),
                pinned: true,
              ),
            if (showPl && Offline.instance.count > 0)
              _Item(
                title: tr('Скачанное'),
                sub: tr('{0} тр. · {1}', [Offline.instance.count, fmtBytes(Offline.instance.bytes)]),
                art: (s) => _Gradient(size: s, icon: Icons.download_done_rounded, green: true),
                onTap: () => _open(context, tr('Скачанное'), () => Offline.instance.tracks, offline: true),
                pinned: true,
              ),
          ];
          _Item plItem(Playlist p) => _Item(
                title: p.name,
                sub: tr('Плейлист • {0}', [
                  tr('{0} тр.', [p.tracks.length])
                ]),
                art: (s) => PlaylistArt(playlist: p, size: s, radius: 6),
                onTap: () => _open(context, p.name, () => p.tracks, playlist: p),
                onLong: () => pickPlaylistCover(context, p),
              );
          // исполнители: подписки (с фото), затем самые слушаемые
          final followed = _filter == 'pl' ? <Map<String, String>>[] : st.follows;
          final arItems = [
            for (final f in followed)
              _Item(
                title: f['name'] ?? '',
                sub: tr('Исполнитель • подписка'),
                art: (s) => CircleAvatar(
                  radius: s / 2,
                  backgroundColor: context.accent.withValues(alpha: 0.22),
                  backgroundImage: f['img'] != null ? NetworkImage(f['img']!) : null,
                  child: f['img'] == null
                      ? Text((f['name'] ?? '?').characters.first.toUpperCase(),
                          style: TextStyle(fontSize: s * 0.38, fontWeight: FontWeight.w800, color: context.accent))
                      : null,
                ),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => ArtistScreen(name: f['name'] ?? '', ytm: f['ytm']))),
                round: true,
              ),
            for (final a in artists.where((a) => !st.isFollowing(a)))
              _Item(
                title: a,
                sub: tr('Исполнитель'),
                art: (s) => CircleAvatar(
                  radius: s / 2,
                  backgroundColor: context.accent.withValues(alpha: 0.22),
                  child: Text(a.characters.first.toUpperCase(),
                      style: TextStyle(fontSize: s * 0.38, fontWeight: FontWeight.w800, color: context.accent)),
                ),
                onTap: () => openArtist(context, Track(id: '', title: '', artist: a)),
                round: true,
              ),
          ];
          final items = [...pinned, if (showPl) ...pls.map(plItem), ...arItems];
          final canDrag = !grid && showPl && st.librarySort == 'custom';
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(context.u(16), context.u(16), context.u(8), 0),
                child: Row(children: [
                  Expanded(child: ScreenTitle(tr('Моя музыка'))),
                  IconButton(
                      tooltip: tr('Добавить'),
                      icon: const Icon(Icons.add_rounded, size: 30),
                      onPressed: () => _add(context)),
                ]),
              ),
            ),
            // фильтры
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(context.u(16), context.u(4), context.u(16), 0),
                child: Wrap(spacing: context.u(8), children: [
                  for (final f in [('pl', tr('Плейлисты')), ('ar', tr('Исполнители'))])
                    ChoiceChip(
                      label: Text(f.$2),
                      selected: _filter == f.$1,
                      onSelected: (v) => setState(() => _filter = v ? f.$1 : null),
                    ),
                ]),
              ),
            ),
            // сортировка и вид
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(context.u(8), context.u(4), context.u(8), context.u(4)),
                child: Row(children: [
                  TextButton.icon(
                    onPressed: () => _pickSort(context),
                    icon: const Icon(Icons.swap_vert_rounded),
                    label: Text(tr(_sorts[st.librarySort] ?? 'Свой порядок')),
                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: grid ? tr('Списком') : tr('Сеткой'),
                    icon: Icon(grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
                    onPressed: () => st.setLibraryView(grid: !grid),
                  ),
                ]),
              ),
            ),
            if (grid)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 5 : 3,
                    mainAxisSpacing: context.u(14),
                    crossAxisSpacing: context.u(12),
                    childAspectRatio: 0.70,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _GridItem(item: items[i], dim: dim),
                    childCount: items.length,
                  ),
                ),
              )
            else if (canDrag) ...[
              SliverList.builder(
                itemCount: pinned.length,
                itemBuilder: (context, i) => _ListItem(item: pinned[i], dim: dim),
              ),
              SliverReorderableList(
                itemCount: pls.length,
                onReorderItem: (from, to) => st.movePlaylist(from, to),
                itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                  key: ObjectKey(pls[i]),
                  index: i,
                  child: Material(type: MaterialType.transparency, child: _ListItem(item: plItem(pls[i]), dim: dim)),
                ),
              ),
              SliverList.builder(
                itemCount: arItems.length,
                itemBuilder: (context, i) => _ListItem(item: arItems[i], dim: dim),
              ),
            ] else
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => _ListItem(item: items[i], dim: dim),
              ),
            if (showPl && st.playlists.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(context.u(16)),
                  child: Text(tr('Плейлистов пока нет — нажмите «+» или «Добавить в плейлист» у трека')),
                ),
              ),
            if (st.history.isNotEmpty && _filter == null) ...[
              SliverToBoxAdapter(child: SectionTitle(tr('Недавно играли'))),
              SliverList.builder(
                itemCount: st.history.length < 30 ? st.history.length : 30,
                itemBuilder: (context, i) =>
                    TrackTile(track: st.history[i], onTap: () => audio.playList(st.history, i)),
              ),
            ],
            SliverToBoxAdapter(child: SizedBox(height: context.u(200))),
          ]);
        },
      ),
    );
  }
}

class _Item {
  final String title;
  final String sub;
  final Widget Function(double size) art;
  final VoidCallback onTap;
  final VoidCallback? onLong;
  final bool pinned;
  final bool round;
  const _Item(
      {required this.title,
      required this.sub,
      required this.art,
      required this.onTap,
      this.onLong,
      this.pinned = false,
      this.round = false});
}

class _ListItem extends StatelessWidget {
  final _Item item;
  final Color? dim;
  const _ListItem({required this.item, this.dim});

  @override
  Widget build(BuildContext context) {
    final s = context.u(64);
    return InkWell(
      onTap: item.onTap,
      onLongPress: item.onLong,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.u(16), vertical: context.u(6)),
        child: Row(children: [
          SizedBox(width: s, height: s, child: item.art(s)),
          SizedBox(width: context.u(12)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              SizedBox(height: context.u(2)),
              Row(children: [
                if (item.pinned) ...[
                  Icon(Icons.push_pin_rounded, size: 14, color: context.accent),
                  SizedBox(width: context.u(4)),
                ],
                Expanded(
                  child: Text(item.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: dim)),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _GridItem extends StatelessWidget {
  final _Item item;
  final Color? dim;
  const _GridItem({required this.item, this.dim});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final s = c.maxWidth;
      return GestureDetector(
        onTap: item.onTap,
        onLongPress: item.onLong,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: s, height: s, child: item.art(s)),
          SizedBox(height: context.u(6)),
          Text(item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text(item.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: dim, fontSize: 12)),
        ]),
      );
    });
  }
}

/// Обложка-градиент для «Мне нравится» / «Скачанное» (как фиолетовое сердце у Spotify).
class _Gradient extends StatelessWidget {
  final double size;
  final IconData icon;
  final bool green;
  const _Gradient({required this.size, required this.icon, this.green = false});

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: green
              ? const [Color(0xFF0E7C4A), Color(0xFF7BE0A8)]
              : [HSLColor.fromColor(a).withLightness(0.3).toColor(), a, const Color(0xFFF3F3F3)],
        ),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.42),
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
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'rename') {
                final n = await askText(context, tr('Переименовать'), tr('Название'), initial: playlist!.name);
                if (n != null) st.renamePlaylist(playlist!, n);
              } else if (v == 'cover') {
                await pickPlaylistCover(context, playlist!);
              } else if (v == 'snake') {
                openSnake(context, tracks());
              } else if (v == 'guess') {
                openGuess(context, tracks());
              } else if (v == 'delete') {
                st.deletePlaylist(playlist!);
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => [
              if (playlist != null) ...[
                PopupMenuItem(
                    value: 'rename',
                    child: ListTile(leading: const Icon(Icons.edit_rounded), title: Text(tr('Переименовать')))),
                PopupMenuItem(
                    value: 'cover',
                    child: ListTile(leading: const Icon(Icons.image_rounded), title: Text(tr('Сменить обложку')))),
              ],
              PopupMenuItem(
                  value: 'snake',
                  child: ListTile(leading: const Icon(Icons.gesture_rounded), title: Text(tr('Игра: змейка')))),
              PopupMenuItem(
                  value: 'guess',
                  child: ListTile(leading: const Icon(Icons.quiz_rounded), title: Text(tr('Игра: угадай песню')))),
              if (playlist != null)
                PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                        leading: const Icon(Icons.delete_outline_rounded), title: Text(tr('Удалить плейлист')))),
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
            if (playlist != null && words.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: context.u(8), bottom: context.u(4)),
                child: Center(
                  child: GestureDetector(
                    onTap: () => pickPlaylistCover(context, playlist!),
                    child: Container(
                      decoration: BoxDecoration(boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, 12)),
                      ]),
                      child: PlaylistArt(playlist: playlist!, size: context.u(190), radius: context.u(8)),
                    ),
                  ),
                ),
              ),
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
