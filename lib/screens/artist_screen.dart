import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../glass.dart';
import '../i18n.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/sc.dart';
import '../services/spotify.dart';
import '../services/store.dart';
import '../services/text_match.dart';
import '../services/wave.dart';
import '../services/ytm_artist.dart';
import '../ui.dart';
import '../widgets.dart';
import 'album_screen.dart';
import 'library_screen.dart';

/// Открыть страницу исполнителя трека. Из плеера/листов — во вкладке (там виден мини-плеер).
void openArtist(BuildContext context, Track t) {
  if (t.artist.trim().isEmpty) return;
  // «A, B и C» — страница первого
  final first = t.artist.split(RegExp(r'\s*(,|&| и | x | feat\.? | ft\.? )\s*')).first.trim();
  pushInTab(context, ArtistScreen(name: first.isEmpty ? t.artist : first, id: t.artistId));
}

/// Всё, что показывает страница — из YouTube Music (официальная дискография) или, если там исполнителя нет,
/// из SoundCloud.
class _Page {
  final String name;
  final String? image;
  final String? monthly;
  final String? subscribers;
  final bool verified;
  final List<Track> top;
  final Map<String, String> plays;
  final List<ScAlbum> albums;
  final List<ScAlbum> singles;
  final List<Track> all;
  final List<YtmArtistRef> similar;
  final String? about;
  const _Page(this.name, this.image, this.monthly, this.subscribers, this.verified, this.top, this.plays, this.albums,
      this.singles, this.all, this.similar, this.about);
}

/// Страница исполнителя как в Spotify: большое фото с именем, слушатели за месяц, «Слушать» / «Вперемешку» /
/// «Волна», «Тебе понравилось», популярное с прослушиваниями, альбомы, синглы, все песни, похожие.
class ArtistScreen extends StatefulWidget {
  final String name;
  final int? id; // аккаунт SoundCloud (если известен)
  final String? ytm; // канал YouTube Music (если известен)
  const ArtistScreen({super.key, required this.name, this.id, this.ytm});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late Future<_Page> _f = _load();
  final _scroll = ScrollController();
  bool _topMore = false;
  bool _aboutOpen = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<_Page> _load() async {
    final b = YtmBrowse.instance;
    YtmArtistPage? y;
    try {
      final id = widget.ytm ?? await b.findArtist(widget.name);
      if (id != null) y = await b.artist(id);
    } catch (_) {}
    if (y != null && (y.top.isNotEmpty || y.singles.isNotEmpty || y.albums.isNotEmpty)) {
      final p = y;
      final r = await Future.wait<Object>([
        p.singlesMore != null
            ? b.discography(p.singlesMore!, p.name).catchError((_) => p.singles)
            : Future.value(p.singles),
        p.albumsMore != null
            ? b.discography(p.albumsMore!, p.name).catchError((_) => p.albums)
            : Future.value(p.albums),
        p.songsPlaylist != null
            ? b.playlist(p.songsPlaylist!, artist: p.name).catchError((_) => <Track>[])
            : Future.value(<Track>[]),
      ]);
      final singles = r[0] as List<ScAlbum>, albums = r[1] as List<ScAlbum>, all = r[2] as List<Track>;
      // у «Топ треков» нет длительности — берём из «Всех песен»
      final secs = {for (final t in all) t.id: t.seconds};
      final top = [
        for (final t in p.top)
          Track(id: t.id, title: t.title, artist: t.artist, seconds: secs[t.id] ?? t.seconds, art: t.art)
      ];
      String? monthly = p.monthly;
      String? image = p.image;
      if (monthly == null || image == null) {
        final sp = await SpotifyService.instance.forArtist(p.name).catchError((_) => null);
        if (sp?.monthlyListeners != null) monthly ??= _count(sp!.monthlyListeners!);
        image ??= sp?.image;
      }
      return _Page(p.name, image, monthly, p.subscribers, true, top, p.plays, albums,
          singles.where((s) => !albums.any((a) => a.ytm == s.ytm)).toList(), all, p.similar, null);
    }
    // запасной путь — SoundCloud
    final sc = ScService.instance;
    final a = widget.id != null ? await sc.artist(widget.id!) : await sc.findArtist(widget.name);
    if (a == null) throw Exception(tr('Исполнитель «{0}» не найден на SoundCloud', [widget.name]));
    final albumsF = sc.artistAlbums(a.id).catchError((_) => <ScAlbum>[]);
    final spF = SpotifyService.instance.forArtist(a.name).then<SpotifyArtist?>((v) => v).catchError((_) => null);
    final r = await Future.wait([sc.artistTop(a.id), sc.artistTracks(a.id)]);
    final rel = await albumsF;
    final sp = await spF;
    return _Page(
      a.name,
      sp?.image ?? a.avatar,
      sp?.monthlyListeners == null ? null : _count(sp!.monthlyListeners!),
      _count(a.followers),
      a.verified,
      r[0],
      const {},
      rel.where((x) => x.kind == 'album' || x.kind == 'compilation').toList(),
      rel.where((x) => x.kind != 'album' && x.kind != 'compilation').toList(),
      r[1],
      const [],
      a.about,
    );
  }

  static String _count(int n) {
    if (n >= 1000000) return tr('{0} млн', [(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')]);
    if (n >= 1000) return tr('{0} тыс.', [(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1).replaceAll('.', ',')]);
    return '$n';
  }

  /// Лайкнутые треки этого исполнителя (как «Тебе понравилось» в Spotify).
  List<Track> _liked(String name) {
    final n = name.toLowerCase();
    return Store.instance.liked
        .where((t) => t.artist.toLowerCase().contains(n) || TextMatch.similarity(t.artist, name) >= 0.8)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Page>(
      future: _f,
      builder: (context, snap) {
        final d = snap.data;
        return Ambient(
          image: d?.image,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: snap.connectionState != ConnectionState.done
                ? Stack(children: [
                    Center(child: CircularProgressIndicator(color: context.accent)),
                    _back(context),
                  ])
                : d == null
                    ? Stack(children: [
                        Center(
                          child: Padding(
                            padding: EdgeInsets.all(context.u(24)),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('${snap.error ?? tr('Не удалось загрузить')}'.replaceFirst('Exception: ', ''),
                                  textAlign: TextAlign.center),
                              SizedBox(height: context.u(12)),
                              FilledButton(onPressed: () => setState(() => _f = _load()), child: Text(tr('Повторить'))),
                            ]),
                          ),
                        ),
                        _back(context),
                      ])
                    : _body(context, d),
          ),
        );
      },
    );
  }

  Widget _back(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(context.u(8)),
          child: GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, size: 40, onTap: () => Navigator.pop(context)),
        ),
      );

  Widget _body(BuildContext context, _Page d) {
    final w = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    final headH = (w * 0.92).clamp(260.0, 420.0);
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.65);
    final playable = d.top.isNotEmpty ? d.top : d.all;
    final liked = _liked(d.name);
    final topN = _topMore ? 10 : 5;
    final topList = [...d.top, ...d.all.where((t) => !d.top.contains(t))].take(10).toList();
    return Stack(children: [
      CustomScrollView(
        controller: _scroll,
        slivers: [
          // шапка: фото во всю ширину, снизу — имя крупно (как в Spotify)
          SliverToBoxAdapter(
            child: SizedBox(
              height: headH,
              child: Stack(fit: StackFit.expand, children: [
                if (d.image != null)
                  Image.network(d.image!,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.3),
                      errorBuilder: (_, __, ___) => const SizedBox())
                else
                  Container(color: context.accent.withValues(alpha: 0.25)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.45, 1],
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: context.u(18),
                  right: context.u(18),
                  bottom: context.u(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(d.name,
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 54,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                              color: Colors.white,
                              letterSpacing: -1.5,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 18)])),
                    ),
                    if (d.verified) ...[
                      SizedBox(height: context.u(6)),
                      Row(children: [
                        Icon(Icons.verified_rounded, color: context.accent, size: context.u(18)),
                        SizedBox(width: context.u(6)),
                        Text(tr('Официальный исполнитель'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(context.u(18), context.u(12), context.u(18), 0),
              child: Text(
                d.monthly != null
                    ? tr('Слушателей за месяц: {0}', [d.monthly])
                    : d.subscribers != null
                        ? tr('Подписчиков: {0}', [d.subscribers])
                        : '',
                style: TextStyle(color: dim, fontSize: 14),
              ),
            ),
          ),
          // кнопки: «Волна» (как «Подписки»), «Вперемешку», большая «Слушать»
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(context.u(18), context.u(10), context.u(18), context.u(4)),
              child: Row(children: [
                OutlinedButton.icon(
                  onPressed: playable.isEmpty ? null : () => Wave.instance.startWith(playable, d.name),
                  icon: const Icon(Icons.waves_rounded, size: 18),
                  label: Text(tr('Волна')),
                  style: OutlinedButton.styleFrom(
                    shape: context.pill,
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: tr('Вперемешку'),
                  iconSize: context.u(30),
                  color: context.accent,
                  onPressed: playable.isEmpty
                      ? null
                      : () {
                          final l = [...(d.all.isNotEmpty ? d.all : playable)]..shuffle();
                          audio.playList(l, 0);
                        },
                  icon: const Icon(Icons.shuffle_rounded),
                ),
                SizedBox(width: context.u(6)),
                ValueListenableBuilder<int>(
                  valueListenable: audio.trackKey,
                  builder: (context, _, __) {
                    final mine = audio.current != null && [...d.top, ...d.all].contains(audio.current);
                    return StreamBuilder<bool>(
                      stream: audio.player.playingStream,
                      builder: (context, s) {
                        final playing = mine && (s.data ?? false);
                        return SizedBox(
                          width: context.u(58),
                          height: context.u(58),
                          child: FilledButton(
                            style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                            onPressed: playable.isEmpty
                                ? null
                                : () {
                                    if (mine) {
                                      playing ? audio.pause() : audio.play();
                                    } else {
                                      audio.playList(playable, 0);
                                    }
                                  },
                            child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.black, size: context.u(34)),
                          ),
                        );
                      },
                    );
                  },
                ),
              ]),
            ),
          ),
          if (liked.isNotEmpty)
            SliverToBoxAdapter(
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: context.u(18)),
                leading: Stack(clipBehavior: Clip.none, children: [
                  CircleAvatar(
                    radius: context.u(26),
                    backgroundImage: d.image != null ? NetworkImage(d.image!) : null,
                    backgroundColor: context.accent.withValues(alpha: 0.3),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                      child: Icon(Icons.favorite_rounded, color: context.accent, size: context.u(16)),
                    ),
                  ),
                ]),
                title: Text(tr('Тебе понравилось'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('{0} тр. · {1}', [liked.length, d.name])),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TrackListScreen(title: tr('Тебе понравилось'), tracks: () => _liked(d.name)))),
              ),
            ),
          if (topList.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionTitle(tr('Популярное'))),
            SliverList.builder(
              itemCount: topList.length < topN ? topList.length : topN,
              itemBuilder: (context, i) => _TopRow(
                index: i,
                track: topList[i],
                plays: d.plays[topList[i].id],
                onTap: () => audio.playList(topList, i),
              ),
            ),
            if (topList.length > 5)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(left: context.u(10)),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _topMore = !_topMore),
                      child: Text(_topMore ? tr('Свернуть') : tr('Показать ещё'),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ),
              ),
          ],
          if (d.albums.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionTitle(tr('Альбомы · {0}', [d.albums.length]))),
            SliverToBoxAdapter(child: AlbumRow(albums: d.albums)),
          ],
          if (d.singles.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionTitle(tr('Синглы и EP · {0}', [d.singles.length]))),
            SliverToBoxAdapter(child: AlbumRow(albums: d.singles)),
          ],
          if (d.all.isNotEmpty)
            SliverToBoxAdapter(
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: context.u(18), vertical: context.u(4)),
                leading: Container(
                  width: context.u(52),
                  height: context.u(52),
                  decoration: BoxDecoration(
                    color: context.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(context.r(8)),
                  ),
                  child: Icon(Icons.queue_music_rounded, color: context.accent),
                ),
                title: Text(tr('Все треки · {0}', [d.all.length]), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(d.name),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => TrackListScreen(title: d.name, tracks: () => d.all))),
              ),
            ),
          if (d.about != null && d.about!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(context.u(18), context.u(8), context.u(18), 0),
                child: GestureDetector(
                  onTap: () => setState(() => _aboutOpen = !_aboutOpen),
                  child: Text(d.about!,
                      maxLines: _aboutOpen ? 30 : 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: dim)),
                ),
              ),
            ),
          if (d.similar.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionTitle(tr('Похожие исполнители'))),
            SliverToBoxAdapter(
              child: SizedBox(
                height: context.u(150),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: context.u(16)),
                  itemCount: d.similar.length,
                  separatorBuilder: (_, __) => SizedBox(width: context.u(14)),
                  itemBuilder: (context, i) {
                    final s = d.similar[i];
                    return GestureDetector(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => ArtistScreen(name: s.name, ytm: s.id))),
                      child: SizedBox(
                        width: context.u(104),
                        child: Column(children: [
                          CircleAvatar(
                            radius: context.u(52),
                            backgroundColor: context.accent.withValues(alpha: 0.2),
                            backgroundImage: s.image != null ? NetworkImage(s.image!) : null,
                          ),
                          SizedBox(height: context.u(6)),
                          Text(s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          if (playable.isEmpty && d.albums.isEmpty && d.singles.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(context.u(24)),
                child:
                    Text(tr('У этого аккаунта нет треков, которые можно слушать целиком'), textAlign: TextAlign.center),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: context.u(200))), // место под мини-плеер и вкладки
        ],
      ),
      // сверху: кнопка «назад»; при прокрутке — полоса с именем (стекло)
      AnimatedBuilder(
        animation: _scroll,
        builder: (context, _) {
          final off = _scroll.hasClients ? _scroll.offset : 0.0;
          final k = ((off - headH * 0.55) / (headH * 0.3)).clamp(0.0, 1.0);
          return SizedBox(
            height: top + context.u(56),
            child: Stack(children: [
              if (k > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: k,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(color: Colors.black.withValues(alpha: 0.45)),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: context.u(56),
                right: context.u(56),
                bottom: context.u(14),
                child: Opacity(
                  opacity: k,
                  child: Text(d.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                ),
              ),
              Positioned(left: 0, top: 0, child: _back(context)),
            ]),
          );
        },
      ),
    ]);
  }
}

/// Строка «Популярного»: номер, обложка, название, прослушивания, меню.
class _TopRow extends StatelessWidget {
  final int index;
  final Track track;
  final String? plays;
  final VoidCallback onTap;
  const _TopRow({required this.index, required this.track, required this.plays, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return ValueListenableBuilder<int>(
      valueListenable: audio.trackKey,
      builder: (context, _, __) {
        final cur = audio.current == track;
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.u(18), vertical: context.u(6)),
            child: Row(children: [
              SizedBox(
                width: context.u(26),
                child: Text('${index + 1}', style: TextStyle(color: cur ? context.accent : dim, fontSize: 15)),
              ),
              Cover(track: track, size: context.u(50), radius: context.u(4)),
              SizedBox(width: context.u(12)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: cur ? context.accent : null)),
                  if (plays != null || track.seconds > 0)
                    Text(plays ?? fmtDuration(track.duration), style: TextStyle(color: dim, fontSize: 13)),
                ]),
              ),
              IconButton(
                icon: Icon(Icons.more_horiz_rounded, color: dim),
                onPressed: () => showTrackMenu(context, track),
              ),
            ]),
          ),
        );
      },
    );
  }
}
