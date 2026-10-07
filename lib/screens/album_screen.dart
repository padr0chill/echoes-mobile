import 'package:flutter/material.dart';

import '../glass.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/sc.dart';
import '../ui.dart';
import '../widgets.dart';
import 'artist_screen.dart';

void openAlbum(BuildContext context, ScAlbum a) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlbumScreen(album: a)));
}

/// Квадратная обложка альбома (или заглушка).
class AlbumArt extends StatelessWidget {
  final ScAlbum album;
  final double size;
  final double radius;
  const AlbumArt({super.key, required this.album, required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    final ph = Container(
      width: size,
      height: size,
      color: context.accent.withValues(alpha: 0.18),
      child: Icon(Icons.album_rounded, color: context.accent, size: size * 0.4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: album.art == null
          ? ph
          : Image.network(album.art!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph),
    );
  }
}

/// Карточка альбома для горизонтальных лент: обложка, название, «Альбом · 2024».
class AlbumCard extends StatelessWidget {
  final ScAlbum album;
  final bool showArtist;
  const AlbumCard({super.key, required this.album, this.showArtist = false});

  @override
  Widget build(BuildContext context) {
    final w = context.u(140);
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return GestureDetector(
      onTap: () => openAlbum(context, album),
      child: SizedBox(
        width: w,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AlbumArt(album: album, size: w, radius: context.u(12)),
          SizedBox(height: context.u(6)),
          Text(album.title,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            [
              if (showArtist) album.artist else album.kindLabel,
              if (album.year != null) '${album.year}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: dim),
          ),
        ]),
      ),
    );
  }
}

/// Горизонтальная лента альбомов.
class AlbumRow extends StatelessWidget {
  final List<ScAlbum> albums;
  final bool showArtist;
  const AlbumRow({super.key, required this.albums, this.showArtist = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // обложка + две строки текста (растут вместе с шрифтом)
      height: context.u(140) + context.u(10) + MediaQuery.textScalerOf(context).scale(38),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.u(16)),
        itemCount: albums.length,
        separatorBuilder: (_, __) => SizedBox(width: context.u(12)),
        itemBuilder: (context, i) => AlbumCard(album: albums[i], showArtist: showArtist),
      ),
    );
  }
}

/// Страница альбома: обложка, исполнитель (ссылка), «Слушать» / «Вперемешку», треки по порядку.
class AlbumScreen extends StatefulWidget {
  final ScAlbum album;
  const AlbumScreen({super.key, required this.album});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late Future<List<Track>> _f = ScService.instance.albumTracks(widget.album.id);

  @override
  Widget build(BuildContext context) {
    final a = widget.album;
    final dim = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.65);
    final size = (MediaQuery.sizeOf(context).width * 0.62).clamp(160.0, context.u(260));
    return Ambient(
      image: a.art,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          FutureBuilder<List<Track>>(
            future: _f,
            builder: (context, snap) {
              final list = snap.data ?? const <Track>[];
              final head = <Widget>[
                SizedBox(height: MediaQuery.paddingOf(context).top + context.u(40)),
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(context.r(20)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4), blurRadius: 40, offset: const Offset(0, 16)),
                      ],
                    ),
                    child: AlbumArt(album: a, size: size, radius: context.u(20)),
                  ),
                ),
                SizedBox(height: context.u(16)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.u(24)),
                  child: Text(a.title,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.15)),
                ),
                SizedBox(height: context.u(4)),
                Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(context.r(12)),
                    onTap: () => openArtist(
                        context, Track(id: '', title: '', artist: a.artist, seconds: 0, artistId: a.artistId)),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.u(8), vertical: context.u(2)),
                      child: Text(a.artist,
                          style: TextStyle(color: context.accent, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                Text(
                  [a.kindLabel, if (a.year != null) '${a.year}', '${a.count} тр.'].join(' · '),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: dim),
                ),
                SizedBox(height: context.u(16)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.u(20)),
                  child: Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: context.u(50),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(shape: context.pill),
                          onPressed: list.isEmpty ? null : () => audio.playList(list, 0),
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                          label:
                              const Text('Слушать', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                    SizedBox(width: context.u(12)),
                    Expanded(
                      child: Glass(
                        radius: context.u(25),
                        shadow: false,
                        child: SizedBox(
                          height: context.u(50),
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              customBorder: context.pill,
                              onTap: list.isEmpty
                                  ? null
                                  : () {
                                      audio.shuffle.value = true; // список перемешает playList
                                      audio.playList(list, DateTime.now().millisecondsSinceEpoch % list.length);
                                    },
                              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.shuffle_rounded),
                                SizedBox(width: 6),
                                Text('Вперемешку', style: TextStyle(fontWeight: FontWeight.w800)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
                SizedBox(height: context.u(8)),
              ];
              Widget? tail;
              if (snap.connectionState != ConnectionState.done) {
                tail = Padding(
                  padding: EdgeInsets.all(context.u(32)),
                  child: Center(child: CircularProgressIndicator(color: context.accent)),
                );
              } else if (snap.hasError) {
                tail = Padding(
                  padding: EdgeInsets.all(context.u(24)),
                  child: Column(children: [
                    const Text('Не удалось загрузить треки альбома', textAlign: TextAlign.center),
                    SizedBox(height: context.u(12)),
                    FilledButton(
                      onPressed: () => setState(() => _f = ScService.instance.albumTracks(a.id)),
                      child: const Text('Повторить'),
                    ),
                  ]),
                );
              } else if (list.isEmpty) {
                tail = Padding(
                  padding: EdgeInsets.all(context.u(24)),
                  child: const Text('В альбоме нет треков, которые можно слушать целиком', textAlign: TextAlign.center),
                );
              }
              return ListView.builder(
                padding: EdgeInsets.only(bottom: context.u(200)), // место под мини-плеер и вкладки
                itemCount: head.length + (tail != null ? 1 : list.length),
                itemBuilder: (context, i) {
                  if (i < head.length) return head[i];
                  if (tail != null) return tail;
                  final j = i - head.length;
                  return TrackTile(
                      track: list[j], onTap: () => audio.playList(list, j), showArtist: list[j].artist != a.artist);
                },
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(context.u(8)),
              child: GlassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded, size: 40, onTap: () => Navigator.pop(context)),
            ),
          ),
        ]),
      ),
    );
  }
}
