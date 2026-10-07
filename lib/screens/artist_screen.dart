import 'package:flutter/material.dart';

import '../glass.dart';
import '../models.dart';
import '../services/audio.dart';
import '../services/sc.dart';
import '../services/spotify.dart';
import '../services/wave.dart';
import '../ui.dart';
import '../widgets.dart';
import 'album_screen.dart';
import '../i18n.dart';

/// Открыть страницу исполнителя трека (аккаунт на SoundCloud: у трека SoundCloud — сразу, иначе — поиском по имени).
void openArtist(BuildContext context, Track t) {
  if (t.artist.trim().isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistScreen(name: t.artist, id: t.artistId)));
}

class _ArtistData {
  final ScArtist artist;
  final List<Track> top;
  final List<ScAlbum> albums;
  final List<Track> all;
  const _ArtistData(this.artist, this.top, this.albums, this.all);
}

/// Страница исполнителя: аватар, подписчики, «Слушать», «Волна по исполнителю», популярное и все треки.
class ArtistScreen extends StatefulWidget {
  final String name;
  final int? id;
  const ArtistScreen({super.key, required this.name, this.id});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late Future<_ArtistData> _f = _load();
  // статистика Spotify — отдельно и не задерживает страницу
  late final Future<SpotifyArtist?> _sp = SpotifyService.instance.forArtist(widget.name);
  bool _aboutOpen = false;
  bool _topMore = false;

  Future<_ArtistData> _load() async {
    final sc = ScService.instance;
    final a = widget.id != null ? await sc.artist(widget.id!) : await sc.findArtist(widget.name);
    if (a == null) throw Exception(tr('Исполнитель «{0}» не найден на SoundCloud', [widget.name]));
    // альбомы не обязательны: если не загрузились — страница всё равно откроется
    final albums = sc.artistAlbums(a.id).catchError((_) => <ScAlbum>[]);
    final r = await Future.wait([sc.artistTop(a.id), sc.artistTracks(a.id)]);
    return _ArtistData(a, r[0], await albums, r[1]);
  }

  String _count(int n) {
    if (n >= 1000000) return tr('{0} млн', [(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')]);
    if (n >= 1000) return tr('{0} тыс.', [(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1).replaceAll('.', ',')]);
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ArtistData>(
      future: _f,
      builder: (context, snap) {
        final d = snap.data;
        return Ambient(
          image: d?.artist.avatar,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(children: [
              if (snap.connectionState != ConnectionState.done)
                Center(child: CircularProgressIndicator(color: context.accent))
              else if (d == null)
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
                )
              else
                _body(context, d),
              // кнопка «назад» — стеклянная, поверх
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(context.u(8)),
                  child: GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    size: 40,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, _ArtistData d) {
    final a = d.artist;
    final all = d.all.isNotEmpty ? d.all : d.top;
    final albums = d.albums.where((x) => x.kind == 'album' || x.kind == 'compilation').toList();
    final singles = d.albums.where((x) => x.kind != 'album' && x.kind != 'compilation').toList();
    final topN = _topMore ? 10 : 5;
    final sub = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.65);
    return ListView(
      padding: EdgeInsets.only(bottom: context.u(200)), // место под мини-плеер и вкладки
      children: [
        SizedBox(height: MediaQuery.paddingOf(context).top + context.u(36)),
        Center(
          child: Container(
            padding: EdgeInsets.all(context.u(4)),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
              boxShadow: [BoxShadow(color: context.accent.withValues(alpha: 0.35), blurRadius: 40)],
            ),
            // фото: со Spotify (обычно лучше качеством), иначе — с SoundCloud
            child: FutureBuilder<SpotifyArtist?>(
              future: _sp,
              builder: (context, s) {
                final img = s.data?.image ?? a.avatar;
                return CircleAvatar(
                  radius: context.u(70),
                  backgroundColor: Theme.of(context).cardColor,
                  backgroundImage: img != null ? NetworkImage(img) : null,
                  child: img == null ? Icon(Icons.person_rounded, size: context.u(64)) : null,
                );
              },
            ),
          ),
        ),
        SizedBox(height: context.u(14)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.u(20)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(a.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.1)),
            ),
            if (a.verified) ...[
              SizedBox(width: context.u(6)),
              Icon(Icons.verified_rounded, color: context.accent, size: context.u(24)),
            ],
          ]),
        ),
        if (a.city != null && a.city!.isNotEmpty) ...[
          SizedBox(height: context.u(2)),
          Text(a.city!, textAlign: TextAlign.center, style: TextStyle(color: sub)),
        ],
        SizedBox(height: context.u(12)),
        // слушатели за месяц (Spotify) и подписчики (SoundCloud — Spotify без аккаунта их не отдаёт)
        FutureBuilder<SpotifyArtist?>(
          future: _sp,
          builder: (context, s) {
            final ml = s.data?.monthlyListeners;
            Widget stat(String value, String label, String src) => Expanded(
                  child: Column(children: [
                    Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    Text(label, textAlign: TextAlign.center, style: TextStyle(color: sub, fontSize: 12)),
                    Text(src, style: TextStyle(color: sub?.withValues(alpha: 0.45), fontSize: 11)),
                  ]),
                );
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: context.u(20)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                stat(
                  s.connectionState != ConnectionState.done ? '…' : (ml == null ? '—' : _count(ml)),
                  tr('слушателей в месяц'),
                  'Spotify',
                ),
                stat(_count(a.followers), tr('подписчиков'), 'SoundCloud'),
              ]),
            );
          },
        ),
        SizedBox(height: context.u(18)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.u(20)),
          child: Row(children: [
            Expanded(
              child: _GlassAction(
                icon: Icons.play_arrow_rounded,
                label: tr('Слушать'),
                filled: true,
                onTap: all.isEmpty ? null : () => audio.playList(d.top.isNotEmpty ? d.top : all, 0),
              ),
            ),
            SizedBox(width: context.u(12)),
            Expanded(
              child: _GlassAction(
                icon: Icons.waves_rounded,
                label: tr('Волна'),
                onTap: all.isEmpty ? null : () => Wave.instance.startWith(all, a.name),
              ),
            ),
          ]),
        ),
        if (a.about != null && a.about!.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(context.u(20), context.u(16), context.u(20), 0),
            child: GestureDetector(
              onTap: () => setState(() => _aboutOpen = !_aboutOpen),
              child: Text(a.about!,
                  maxLines: _aboutOpen ? 30 : 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub)),
            ),
          ),
        if (d.top.isNotEmpty) ...[
          SectionTitle(tr('Популярное')),
          for (var i = 0; i < d.top.length && i < topN; i++)
            TrackTile(track: d.top[i], onTap: () => audio.playList(d.top, i), showArtist: false),
          if (d.top.length > 5)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _topMore = !_topMore),
                child: Text(_topMore ? tr('Свернуть') : tr('Показать ещё')),
              ),
            ),
        ],
        if (albums.isNotEmpty) ...[
          SectionTitle(tr('Альбомы · {0}', [albums.length])),
          AlbumRow(albums: albums),
        ],
        if (singles.isNotEmpty) ...[
          SectionTitle(tr('Синглы и EP · {0}', [singles.length])),
          AlbumRow(albums: singles),
        ],
        if (d.all.isNotEmpty) ...[
          SectionTitle(tr('Все треки · {0}', [d.all.length])),
          for (var i = 0; i < d.all.length; i++)
            TrackTile(track: d.all[i], onTap: () => audio.playList(d.all, i), showArtist: false),
        ],
        if (all.isEmpty)
          Padding(
            padding: EdgeInsets.all(context.u(24)),
            child: Text(tr('У этого аккаунта нет треков, которые можно слушать целиком'), textAlign: TextAlign.center),
          ),
      ],
    );
  }
}

class _GlassAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  const _GlassAction({required this.icon, required this.label, this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final content = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: filled ? Colors.black : null),
      SizedBox(width: context.u(6)),
      Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: filled ? Colors.black : null)),
    ]);
    final h = context.u(50);
    if (filled) {
      return SizedBox(
        height: h,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(shape: context.pill),
          child: content,
        ),
      );
    }
    return Glass(
      radius: h / 2,
      shadow: false,
      child: SizedBox(
        height: h,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(customBorder: context.pill, onTap: onTap, child: content),
        ),
      ),
    );
  }
}
